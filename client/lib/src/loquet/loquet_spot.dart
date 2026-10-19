// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../app_scope.dart';
import '../app_state.dart';
import '../design/logo.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../events/app_events.dart';
import '../settings/settings.dart';
import 'line_bank.dart';
import 'loquet.dart';
import 'loquet_pose.dart';

/// Where Loquet sits, and his size there.
enum LoquetPlacement {
  lock(260),
  tree(56),
  rail(36),
  dialog(64),
  empty(88),
  banner(40);

  const LoquetPlacement(this.size);
  final double size;
}

/// A place for Loquet: the shared controller's face (or a fixed [mood] and [line]), the logo when the
/// mascot is off or outside the app.
class LoquetSpot extends StatefulWidget {
  const LoquetSpot({
    super.key,
    required this.placement,
    this.mood,
    this.line,
    this.params = const {},
    this.eyeX,
  });

  final LoquetPlacement placement;
  final LoquetMood? mood;
  final LineKey? line;
  final Map<String, String> params;
  final double? eyeX;

  @override
  State<LoquetSpot> createState() => _LoquetSpotState();
}

class _LoquetSpotState extends State<LoquetSpot> {
  final _bank = LineBank();
  AppState? _state;
  Object? _textFor;
  String? _text;
  DateTime? _hoverSince;
  Offset _drag = Offset.zero;
  LoquetFx? _landing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context
        .dependOnInheritedWidgetOfExactType<AppScope>()
        ?.notifier;
    if (state != _state) {
      _state?.loquet.detach();
      state?.loquet.attach();
      _state = state;
    }
  }

  @override
  void dispose() {
    _state?.loquet.detach();
    super.dispose();
  }

  /// The text is chosen once per fixed line, else once per reaction, so rebuilds never swap variants.
  String? _line(AppLocalizations l, AppState state) {
    final loquet = state.loquet;
    final key = widget.line ?? loquet.line;
    if (key == null) return _text = _textFor = null;
    final identity = widget.line ?? loquet.current;
    if (identity != _textFor || _text == null) {
      _textFor = identity;
      _text = _bank.text(
        l,
        key,
        widget.line != null ? widget.params : loquet.params,
      );
    }
    return _text;
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final size = widget.placement.size;
    if (state == null || !state.loquet.visible) return UfLogo(size: size);
    final l = AppLocalizations.of(context);
    final still = UfMotion.of(context) == UfMotion.still;
    final loquet = state.loquet;
    return ListenableBuilder(
      listenable: loquet,
      builder: (context, _) {
        if (!loquet.visible) return UfLogo(size: size);
        final mood = widget.mood ?? loquet.mood;
        final bubbles =
            loquet.mode == LoquetMode.on &&
            widget.placement != LoquetPlacement.rail &&
            widget.placement !=
                LoquetPlacement.tree; // the status card prints the line itself
        final text = bubbles ? _line(l, state) : null;
        final lively = loquet.mode == LoquetMode.on && !still;
        Widget face = GestureDetector(
          onTap: () => state.emit(const LoquetClicked()),
          onPanUpdate: lively && widget.placement == LoquetPlacement.tree
              ? (d) => setState(() => _drag += d.delta)
              : null,
          onPanEnd: lively && widget.placement == LoquetPlacement.tree
              ? (_) {
                  setState(() {
                    _drag = Offset.zero;
                    _landing = LoquetFx.hop;
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _landing = null);
                  });
                }
              : null,
          child: Transform.translate(
            offset: _drag,
            child: Transform.rotate(
              // dangles with the finger, ±15°
              angle: (_drag.dx / 120).clamp(-0.26, 0.26),
              child: Loquet(
                mood: mood,
                accessory: loquet.accessory,
                size: size,
                eyeX: widget.eyeX ?? loquet.eyeX,
                still: still,
                life: loquet.life,
                fx: _landing ?? loquet.fx,
                semanticLabel: loquetLabel(l, mood),
              ),
            ),
          ),
        );
        if (lively) {
          // a long hover: the eyes follow the cursor
          face = MouseRegion(
            onEnter: (_) => _hoverSince = DateTime.now(),
            onExit: (_) => _hoverSince = null,
            onHover: (e) {
              final since = _hoverSince;
              if (since != null &&
                  DateTime.now().difference(since) >=
                      const Duration(seconds: 1)) {
                loquet.watch((e.localPosition.dx / size).clamp(0, 1));
              }
            },
            child: face,
          );
        }
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            face,
            if (text != null)
              Positioned(
                bottom: size + 6, // above his head: the layout never shifts
                child: LoquetBubble(text: text),
              ),
          ],
        );
      },
    );
  }
}

/// What Loquet says, in a small floating panel.
class LoquetBubble extends StatelessWidget {
  const LoquetBubble({
    super.key = const Key('loquet-bubble'),
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return Semantics(
      label: AppLocalizations.of(context).loquetBubbleLabel(text),
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.8, end: 1),
        duration: UfMotion.of(context).fast,
        curve: UfMotion.curve,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Text(text, style: TextStyle(color: colors.text)),
        ),
      ),
    );
  }
}
