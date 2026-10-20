// SPDX-License-Identifier: Apache-2.0
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../debug_trace.dart';
import 'tokens.dart';

class UfMotion {
  const UfMotion._(this.instant, this.fast, this.base, this.slow);

  /// Hover colour of a tree row.
  final Duration instant;

  /// Hover, press, focus, check marks and every exit.
  final Duration fast;

  /// Switches, segmented controls, lists opening, dialogs, notifications in.
  final Duration base;

  /// Row to inspector, screen changes, unlock to main.
  final Duration slow;

  static const normal = UfMotion._(
    Duration(milliseconds: 90),
    Duration(milliseconds: 120),
    Duration(milliseconds: 160),
    Duration(milliseconds: 280),
  );
  static const still = UfMotion._(
    Duration.zero,
    Duration.zero,
    Duration.zero,
    Duration.zero,
  );

  /// In-place changes.
  static const standard = Cubic(0.2, 0, 0, 1);

  /// What appears or grows.
  static const enter = Cubic(0.05, 0.7, 0.1, 1);

  /// What leaves, faster than it came.
  static const exit = Cubic(0.3, 0, 1, 1);

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

/// [alert] marks the dialog as an `alertdialog` and disables barrier dismiss; Escape still closes it (null).
Future<T?> showUfDialog<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool alert = false,
}) {
  final motion = UfMotion.of(context);
  trace(TraceArea.ui, 'dialog open');
  return Navigator.of(context, rootNavigator: true).push<T>(
    _UfDialogRoute<T>(
      reverse: motion.fast,
      transitionDuration: motion.base,
      barrierDismissible: !alert,
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
        final eased = CurvedAnimation(
          parent: animation,
          curve: UfMotion.enter,
          reverseCurve: UfMotion.exit,
        );
        return FadeTransition(
          opacity: eased,
          child: ScaleTransition(
            scale: Tween(begin: 0.98, end: 1.0).animate(eased),
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

/// The child fades in while it grows from 96 %; plays once, at [UfMotion.slow].
class GrowIn extends StatelessWidget {
  const GrowIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: UfMotion.of(context).slow,
    curve: UfMotion.enter,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
    ),
    child: child,
  );
}
