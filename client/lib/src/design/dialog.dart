// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../loquet/loquet_pose.dart';
import '../loquet/loquet_spot.dart';
import 'buttons.dart';
import 'motion.dart';

export 'buttons.dart' show dangerButtonStyle, dangerQuietStyle;
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

  /// Loquet, or a seal.
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
          style: text.bodyMedium!.copyWith(color: colors.muted, fontSize: 13.5),
        ),
    ];
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
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 14,
              children: [
                if (heading.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 14,
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
      ),
    );
  }
}

/// "Annuler" in the body colour, next to a primary action.
class CancelButton extends StatelessWidget {
  const CancelButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
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
              const LoquetSpot(
                placement: LoquetPlacement.dialog,
                mood: LoquetMood.concerned,
              ),
              Expanded(
                child: Text(
                  question,
                  style: Theme.of(dialog).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ],
      );
    }) ??
    false;
