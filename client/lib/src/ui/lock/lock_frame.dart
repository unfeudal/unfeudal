// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../design/buttons.dart';
import '../../design/icons.dart';
import '../../design/logo.dart';
import '../../design/tokens.dart';
import '../../loquet/lock_mapping.dart';
import '../../loquet/loquet_pose.dart';
import '../../loquet/loquet_spot.dart';

export '../../design/buttons.dart' show BusyButton;
export '../../design/field.dart' show UfErrorLine;

/// Every screen before the vault: the form on the left (mark, step, title, fields, actions), the side panel on
/// the right. The side panel holds Loquet, whose face follows the lock machine.
class LockFrame extends StatelessWidget {
  const LockFrame({
    super.key,
    required this.title,
    this.step,
    this.subtitle,
    required this.children,
    this.eyeX = 0.5,
  });

  /// Where Loquet looks while an address is typed: from 0 (left) to 1 (right).
  final double eyeX;

  final String title;

  /// The "Step 1 of 2" label on two-step screens.
  final String? step;
  final String? subtitle;
  final List<Widget> children;

  /// The ground of the form, and of the title bar above it.
  static Color background(BuildContext context) => UfColors.of(context).bg;

  // Below this width the side panel is dropped and the form takes the window.
  static const _sideBreakpoint = 880.0;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 24,
      children: [
        Row(
          spacing: 10,
          children: [
            UfLogo(size: 28, color: colors.text),
            Text(
              'unfeudal',
              style: text.titleMedium!.copyWith(
                fontSize: 21,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            if (step case final step?)
              Text(step, style: text.labelSmall!.copyWith(color: colors.muted)),
            Text(title, style: text.displaySmall),
            if (subtitle case final subtitle?)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Text(
                  subtitle,
                  style: text.bodyMedium!.copyWith(color: colors.muted),
                ),
              ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: children,
        ),
      ],
    );
    // a Material, not a coloured box: list tiles in the form paint on it
    final panel = Material(
      color: background(context),
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 72, vertical: 40),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 456,
              minHeight: (box.maxHeight - 80).clamp(0, double.infinity),
            ),
            child: content,
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _sideBreakpoint) return panel;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 600, child: panel),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.side,
                  border: Border(left: BorderSide(color: colors.line)),
                ),
                child: Center(child: _hero(context)),
              ),
            ),
          ],
        );
      },
    );
  }
}

extension on LockFrame {
  Widget _hero(BuildContext context) {
    final state = context
        .dependOnInheritedWidgetOfExactType<AppScope>()
        ?.notifier;
    if (state == null) {
      return const LoquetSpot(placement: LoquetPlacement.lock);
    }
    return ListenableBuilder(
      listenable: Listenable.merge([state.lockMachine, state.loquet]),
      builder: (context, _) {
        final face = loquetForLock(state.lockMachine.state);
        // three wrong passwords: he hides his face over the table's mood
        final covering = state.loquet.current?.mood == LoquetMood.covering;
        return LoquetSpot(
          key: const Key('loquet-spot-lock'),
          placement: LoquetPlacement.lock,
          mood: covering ? LoquetMood.covering : face.mood,
          line: face.line,
          params: {'name': ?state.stored?.displayName},
          eyeX: eyeX,
        );
      },
    );
  }
}

/// The 40 px primary action, then the other ways in as links over a `line`.
class LockActions extends StatelessWidget {
  const LockActions({super.key, required this.primary, this.links = const []});

  final Widget primary;
  final List<Widget> links;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16,
      children: [
        FilledButtonTheme(
          data: FilledButtonThemeData(
            style: largeButton(theme.textTheme)
                .merge(theme.filledButtonTheme.style),
          ),
          child: primary,
        ),
        if (links.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.line)),
            ),
            child: TextButtonTheme(
              data: TextButtonThemeData(
                style: ButtonStyle(
                  foregroundColor: WidgetStatePropertyAll(colors.accentText),
                  backgroundColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  textStyle: WidgetStatePropertyAll(
                    theme.textTheme.labelLarge!.copyWith(fontSize: 13.5),
                  ),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(vertical: 4),
                  ),
                  minimumSize: const WidgetStatePropertyAll(Size.zero),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ).merge(theme.textButtonTheme.style),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: links,
              ),
            ),
          ),
      ],
    );
  }
}

/// The warning shape in `warn` beside a note: the master-password warning before an account is created.
class LockNotice extends StatelessWidget {
  const LockNotice(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(UfIcons.warning, size: 16, color: colors.warn),
        ),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(fontSize: 13),
          ),
        ),
      ],
    );
  }
}
