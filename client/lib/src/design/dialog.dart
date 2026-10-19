// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import 'logo.dart';
import 'motion.dart';
import 'tokens.dart';

/// A dialog: an optional mark left of the title and message, then content, then actions on the right.
class UfDialog extends StatelessWidget {
  const UfDialog({
    super.key,
    this.title,
    this.message,
    this.leading,
    this.children = const [],
    required this.actions,
    this.width = 540,
  });

  final String? title;
  final String? message;

  /// Loquet's place; the logo or a seal until then.
  final Widget? leading;
  final List<Widget> children;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    final heading = [
      if (title case final title?) Text(title, style: text.titleLarge),
      if (message case final message?)
        Text(
          message,
          style: text.bodyLarge!.copyWith(color: colors.muted, height: 1.5),
        ),
    ];
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Container(
        constraints: BoxConstraints(maxWidth: width),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          boxShadow: [
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 80,
              offset: Offset(0, 30),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              if (heading.isNotEmpty)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 16,
                  children: [
                    ?leading,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 6,
                        children: heading,
                      ),
                    ),
                  ],
                ),
              ...children,
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Primary button for a destructive or risky answer: `danger` fill, `onDanger` text.
ButtonStyle dangerButtonStyle(UfColors colors) => FilledButton.styleFrom(
  backgroundColor: colors.danger,
  foregroundColor: colors.onDanger,
);

/// A text button in the body colour, for "Annuler" next to a primary action.
ButtonStyle quietButtonStyle(UfColors colors) =>
    TextButton.styleFrom(foregroundColor: colors.text);

/// "Annuler" in the body colour, next to a primary action.
class CancelButton extends StatelessWidget {
  const CancelButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    style: quietButtonStyle(UfColors.of(context)),
    onPressed: onPressed,
    child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
  );
}

/// Yes or no before something goes to the trash or signs out: the question, Cancel and a danger action.
Future<bool> confirmDanger(
  BuildContext context, {
  required String question,
  required String action,
}) async =>
    await showUfDialog<bool>(context, alert: true, (dialog) {
      final colors = UfColors.of(dialog);
      return UfDialog(
        width: 480,
        actions: [
          CancelButton(onPressed: () => Navigator.pop(dialog, false)),
          FilledButton(
            key: const Key('confirm-yes'),
            style: dangerButtonStyle(colors),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(action),
          ),
        ],
        children: [
          Row(
            spacing: 16,
            children: [
              // Loquet's place
              UfLogo(size: 48, color: colors.muted),
              Expanded(
                child: Text(
                  question,
                  style: Theme.of(dialog).textTheme.titleMedium!
                      .copyWith(fontSize: 16),
                ),
              ),
            ],
          ),
        ],
      );
    }) ??
    false;
