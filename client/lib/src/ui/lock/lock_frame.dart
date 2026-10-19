// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../design/icons.dart';
import '../../design/logo.dart';
import '../../design/tokens.dart';

/// Every screen before the vault: the form on the left (mark, step, title, fields, actions), the side panel on
/// the right. The side panel holds the logo until Loquet takes its place.
class LockFrame extends StatelessWidget {
  const LockFrame({
    super.key,
    required this.title,
    this.step,
    this.subtitle,
    required this.children,
  });

  final String title;

  /// "Étape 1 sur 2" on two-step screens.
  final String? step;
  final String? subtitle;
  final List<Widget> children;

  /// The form's background: `side` when light so the `field` fills stay visible, `bg` when dark.
  static Color background(BuildContext context) {
    final colors = UfColors.of(context);
    return Theme.of(context).brightness == Brightness.light
        ? colors.side
        : colors.bg;
  }

  /// Below this width the side panel is dropped and the form takes the window.
  static const _sideBreakpoint = 880.0;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final form = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 72, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 456),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 22,
          children: [
            Row(
              spacing: 10,
              children: [
                UfLogo(size: 30, color: colors.accent),
                Text(
                  'unfeudal',
                  style: text.titleMedium!.copyWith(
                    fontSize: 22,
                    letterSpacing: -0.55,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                if (step case final step?)
                  Text(
                    step,
                    style: text.labelMedium!.copyWith(color: colors.muted),
                  ),
                Text(title, style: text.headlineLarge!.copyWith(height: 1.05)),
                if (subtitle case final subtitle?)
                  Text(
                    subtitle,
                    style: text.bodyLarge!.copyWith(color: colors.muted),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 14,
              children: children,
            ),
          ],
        ),
      ),
    );
    // a Material, not a coloured box: list tiles in the form paint on it
    final panel = Material(
      color: background(context),
      child: Align(alignment: Alignment.centerLeft, child: form),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _sideBreakpoint) return panel;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 600, child: panel),
            Expanded(
              child: ColoredBox(
                color: light ? colors.rail : colors.side,
                child: Center(child: UfLogo(size: 220, color: colors.accent)),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The inline primary action and the left-aligned links under a lock form.
class LockActions extends StatelessWidget {
  const LockActions({super.key, required this.primary, this.links = const []});

  final Widget primary;
  final List<Widget> links;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 4,
    children: [
      primary,
      if (links.isNotEmpty) const SizedBox(height: 8),
      for (final link in links)
        TextButtonTheme(
          data: TextButtonThemeData(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ).merge(Theme.of(context).textButtonTheme.style),
          ),
          child: link,
        ),
    ],
  );
}

/// A form error under the fields: `danger`, semibold.
class LockError extends StatelessWidget {
  const LockError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: TextStyle(
      color: UfColors.of(context).danger,
      fontWeight: FontWeight.w600,
    ),
  );
}

/// An ocre line with the warning shape: the master-password warning before an account is created.
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
          child: Icon(UfIcons.warning, size: 16, color: colors.warnText),
        ),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(color: colors.warnText),
          ),
        ),
      ],
    );
  }
}

/// A primary button's label that turns into a spinner and "Vérification…" while the password key is derived.
class BusyLabel extends StatelessWidget {
  const BusyLabel({super.key, required this.busy, required this.label});

  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (!busy) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: UfColors.of(context).accentFg,
          ),
        ),
        Text(AppLocalizations.of(context).passwordChecking),
      ],
    );
  }
}
