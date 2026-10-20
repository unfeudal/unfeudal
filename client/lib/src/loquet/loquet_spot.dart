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
import 'loquet_controller.dart';
import 'loquet_pose.dart';
import 'mood.dart';

/// Where Loquet sits, and his size there.
enum LoquetPlacement {
  lock(260),

  /// The sidebar footer: his face, the account name and his reason line.
  sidebar(28),

  /// The title bar while the sidebar is hidden.
  titleBar(24),
  dialog(40),
  empty(88);

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
    this.name,
  });

  final LoquetPlacement placement;
  final LoquetMood? mood;
  final LineKey? line;
  final Map<String, String> params;
  final double? eyeX;

  /// The account name above his line, in the sidebar footer.
  final String? name;

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

  // The text is chosen once per fixed line, else once per reaction, so rebuilds never swap variants.
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
        final text =
            loquet.mode == LoquetMode.on &&
                widget.placement != LoquetPlacement.titleBar
            ? _line(l, state)
            : null;
        final lively = loquet.mode == LoquetMode.on && !still;
        final drawn = _face(state, mood, lively: lively, still: still);
        final face = lively ? _followingCursor(loquet, drawn) : drawn;
        if (widget.placement == LoquetPlacement.sidebar) {
          // the footer is the sidebar's bubble: the account name over his line
          return _SidebarFooter(
            face: face,
            name: widget.name,
            caption:
                // reasons asked by a click win over a fixed line (an empty vault)
                (loquet.reasons ? _reasons(l, loquet.engine.health) : null) ??
                text ??
                loquetLabel(l, mood),
          );
        }
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            face,
            if (text != null)
              // Above his head, so the layout never shifts.
              Positioned(
                bottom: size + 6,
                child: LoquetBubble(text: text),
              ),
          ],
        );
      },
    );
  }

  Widget _face(
    AppState state,
    LoquetMood mood, {
    required bool lively,
    required bool still,
  }) {
    final loquet = state.loquet;
    final draggable = lively && widget.placement == LoquetPlacement.sidebar;
    return GestureDetector(
      onTap: () => state.emit(const LoquetClicked()),
      onPanUpdate: draggable ? (d) => setState(() => _drag += d.delta) : null,
      onPanEnd: draggable ? (_) => _land() : null,
      child: Transform.translate(
        offset: _drag,
        child: Transform.rotate(
          // Dangles with the finger, up to 15 degrees either way.
          angle: (_drag.dx / 120).clamp(-0.26, 0.26),
          child: Loquet(
            mood: mood,
            accessory: loquet.accessory,
            size: widget.placement.size,
            eyeX: widget.eyeX ?? loquet.eyeX,
            still: still,
            life: loquet.life,
            fx: _landing ?? loquet.fx,
            semanticLabel: loquetLabel(AppLocalizations.of(context), mood),
          ),
        ),
      ),
    );
  }

  void _land() {
    setState(() {
      _drag = Offset.zero;
      _landing = LoquetFx.hop;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _landing = null);
    });
  }

  // a long hover: the eyes follow the cursor
  Widget _followingCursor(LoquetController loquet, Widget face) => MouseRegion(
    onEnter: (_) => _hoverSince = DateTime.now(),
    onExit: (_) => _hoverSince = null,
    onHover: (e) {
      final since = _hoverSince;
      if (since != null &&
          DateTime.now().difference(since) >= const Duration(seconds: 1)) {
        loquet.watch((e.localPosition.dx / widget.placement.size).clamp(0, 1));
      }
    },
    child: face,
  );
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.face,
    required this.name,
    required this.caption,
  });

  final Widget face;
  final String? name;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall!;
    return Row(
      spacing: 8,
      children: [
        face,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (name case final name?)
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Text(
                caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: small.copyWith(color: UfColors.of(context).muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _reasons(AppLocalizations l, VaultHealth h) => [
  for (final r in h.reasons)
    switch (r) {
      MoodReason.verify => l.loquetReasonVerify(h.verifyOver7Days),
      MoodReason.conflicts => l.loquetReasonConflicts(h.conflicts),
      MoodReason.oldKeys => l.loquetReasonOldKeys(h.keysOver5Years),
      MoodReason.staleSync => l.loquetReasonStaleSync,
    },
].join(' · ');

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
        curve: UfMotion.standard,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: UfRadius.card,
            boxShadow: UfElevation.floating(colors),
          ),
          child: Text(text, style: TextStyle(color: colors.text)),
        ),
      ),
    );
  }
}
