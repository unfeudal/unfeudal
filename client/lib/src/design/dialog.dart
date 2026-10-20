// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../loquet/loquet_pose.dart';
import '../loquet/loquet_spot.dart';
import 'buttons.dart';
import 'motion.dart';
import 'tokens.dart';

export 'buttons.dart' show dangerButtonStyle, dangerQuietStyle;

/// A dialog: an optional mark left of the title and message, then content, then actions on the right.
class UfDialog extends StatelessWidget {
  const UfDialog({
    super.key,
    this.title,
    this.message,
    this.leading,
    this.children = const [],
    required this.actions,
    this.width = 440,
  });

  final String? title;
  final String? message;

  /// Loquet, or a seal.
  final Widget? leading;
  final List<Widget> children;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxWidth: width),
        decoration: BoxDecoration(
          borderRadius: UfRadius.dialog,
          boxShadow: UfElevation.dialog(colors),
        ),
        // a Material, so list tiles inside paint their own ink
        child: Material(
          color: colors.panel,
          borderRadius: UfRadius.dialog,
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                if (title != null || message != null)
                  _DialogHeading(
                    leading: leading,
                    title: title,
                    message: message,
                  ),
                ...children,
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogHeading extends StatelessWidget {
  const _DialogHeading({
    required this.leading,
    required this.title,
    required this.message,
  });

  final Widget? leading;
  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        ?leading,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              if (title case final title?) Text(title, style: text.titleLarge),
              if (message case final message?)
                Text(
                  message,
                  style: text.bodyMedium!.copyWith(
                    color: colors.muted,
                    fontSize: 13.5,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Annuler" as a secondary button, next to a primary action. [autofocus] gives it the dialog's initial focus,
/// for a risky question.
class CancelButton extends StatelessWidget {
  const CancelButton({
    super.key,
    required this.onPressed,
    this.autofocus = false,
  });

  final VoidCallback? onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    autofocus: autofocus,
    child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
  );
}

/// Yes or no before something goes to the trash or signs out: Loquet beside the question, then Cancel (focused)
/// and a danger action. Escape or a click on the scrim answers no.
Future<bool> confirmDanger(
  BuildContext context, {
  required String question,
  required String action,
  String? message,
}) async =>
    await showUfDialog<bool>(context, (dialog) {
      final colors = UfColors.of(dialog);
      return UfDialog(
        leading: const LoquetSpot(
          placement: LoquetPlacement.dialog,
          mood: LoquetMood.concerned,
        ),
        title: question,
        message: message,
        actions: [
          CancelButton(
            autofocus: true,
            onPressed: () => Navigator.pop(dialog, false),
          ),
          FilledButton(
            key: const Key('confirm-yes'),
            style: dangerButtonStyle(colors),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(action),
          ),
        ],
      );
    }) ??
    false;
