// SPDX-License-Identifier: Apache-2.0
import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../debug_trace.dart';
import 'tokens.dart';

class UfMotion {
  const UfMotion._(this.fast, this.base, this.slow, this.shake);

  final Duration fast, base, slow, shake;

  static const normal = UfMotion._(
    Duration(milliseconds: 160),
    Duration(milliseconds: 240),
    Duration(milliseconds: 420),
    Duration(milliseconds: 360),
  );
  static const still = UfMotion._(
    Duration.zero,
    Duration.zero,
    Duration.zero,
    Duration.zero,
  );
  static const curve = Cubic(0.2, 0.8, 0.2, 1);

  /// [still] under performance mode or the OS reduce-motion setting.
  static UfMotion of(BuildContext context) {
    final performance =
        context
            .dependOnInheritedWidgetOfExactType<MotionScope>()
            ?.performanceMode ??
        false;
    return performance || MediaQuery.disableAnimationsOf(context)
        ? still
        : normal;
  }
}

class MotionScope extends InheritedWidget {
  const MotionScope({
    super.key,
    required this.performanceMode,
    required super.child,
  });

  final bool performanceMode;

  @override
  bool updateShouldNotify(MotionScope oldWidget) =>
      performanceMode != oldWidget.performanceMode;
}

class ShakeOnError extends StatefulWidget {
  const ShakeOnError({super.key, required this.trigger, required this.child});

  final Object? trigger;
  final Widget child;

  @override
  State<ShakeOnError> createState() => _ShakeOnErrorState();
}

class _ShakeOnErrorState extends State<ShakeOnError>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);

  @override
  void didUpdateWidget(ShakeOnError oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger == oldWidget.trigger) return;
    final motion = UfMotion.of(context);
    if (motion == UfMotion.still) return;
    _controller.duration = motion.shake;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final t = _controller.value;
      final dx = 8 * (1 - t) * math.sin(t * 3 * 2 * math.pi);
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
    child: widget.child,
  );
}

/// [alert] marks the dialog as an `alertdialog` and disables barrier dismiss; Escape still closes it (null).
Future<T?> showUfDialog<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool dismissible = true,
  bool alert = false,
}) {
  final motion = UfMotion.of(context);
  trace(TraceArea.ui, 'dialog open');
  return Navigator.of(context, rootNavigator: true).push<T>(
    _UfDialogRoute<T>(
      reverse: motion.fast,
      transitionDuration: motion.base,
      barrierDismissible: dismissible && !alert,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor:
          Theme.of(context).extension<UfColors>()?.scrim ?? Colors.black54,
      pageBuilder: (context, _, _) {
        final content = builder(context);
        if (!alert) return content;
        return Semantics(
          role: SemanticsRole.alertDialog,
          scopesRoute: true,
          explicitChildNodes: true,
          child: Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) => Navigator.of(context).maybePop(),
              ),
            },
            child: Focus(autofocus: true, child: content),
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final eased = CurvedAnimation(parent: animation, curve: UfMotion.curve);
        return FadeTransition(
          opacity: eased,
          child: AnimatedBuilder(
            animation: eased,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, 10 * (1 - eased.value)),
              child: child,
            ),
            child: child,
          ),
        );
      },
    ),
  );
}

class _UfDialogRoute<T> extends RawDialogRoute<T> {
  _UfDialogRoute({
    required this.reverse,
    required super.pageBuilder,
    required super.transitionDuration,
    required super.barrierDismissible,
    required super.barrierLabel,
    required super.barrierColor,
    required super.transitionBuilder,
  });

  final Duration reverse;

  @override
  Duration get reverseTransitionDuration => reverse;
}

/// Container transform, light: the child grows out of [from] (a global point, the control that opened it)
/// while it fades in; without [from] it only fades. Plays once, at [UfMotion.slow].
class GrowFrom extends StatefulWidget {
  const GrowFrom({super.key, required this.from, required this.child});

  final Offset? from;
  final Widget child;

  @override
  State<GrowFrom> createState() => _GrowFromState();
}

class _GrowFromState extends State<GrowFrom>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);
  late final _t = CurvedAnimation(parent: _controller, curve: UfMotion.curve);

  /// [GrowFrom.from] relative to the child's centre, read once it is laid out.
  Offset? _origin;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = UfMotion.of(context).slow;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (widget.from case final from? when box is RenderBox && box.hasSize) {
        _origin = box.globalToLocal(from) - box.size.center(Offset.zero);
      }
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (context, child) => Opacity(
      opacity: _t.value,
      child: Transform.scale(
        scale: 0.85 + 0.15 * _t.value,
        origin: _origin,
        child: child,
      ),
    ),
    child: widget.child,
  );
}
