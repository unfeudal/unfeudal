// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'buttons.dart';
import 'icons.dart';
import 'tokens.dart';

enum BannerTone { info, warn, danger }

class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.tone,
    required this.message,
    this.action,
    this.secondAction,
    this.onDismiss,
    this.actionKey,
    this.secondActionKey,
    this.dismissKey,
    this.dismissTooltip,
  });

  final BannerTone tone;
  final String message;
  final (String, VoidCallback)? action;
  final (String, VoidCallback)? secondAction;
  final VoidCallback? onDismiss;
  final Key? actionKey;
  final Key? secondActionKey;
  final Key? dismissKey;

  /// Defaults to the generic "Dismiss".
  final String? dismissTooltip;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    // status never by colour alone: each tone has its own icon shape
    final (color, fill, icon) = switch (tone) {
      BannerTone.info => (colors.accentText, colors.select, UfIcons.info),
      BannerTone.warn => (colors.warn, colors.warnSoft, UfIcons.warning),
      BannerTone.danger => (
        colors.danger,
        colors.dangerSoft,
        UfIcons.warningOctagon,
      ),
    };
    // full width above the main area; actions are small secondary buttons
    return Material(
      color: fill,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
          child: Row(
            spacing: 12,
            children: [
              Icon(icon, color: color, size: 16),
              Expanded(child: Text(message)),
              if (action case (final label, final onPressed))
                OutlinedButton(
                  key: actionKey,
                  style: smallButton,
                  onPressed: onPressed,
                  child: Text(label),
                ),
              if (secondAction case (final label, final onPressed))
                TextButton(
                  key: secondActionKey,
                  style: smallButton,
                  onPressed: onPressed,
                  child: Text(label),
                ),
              if (onDismiss != null)
                IconButton(
                  key: dismissKey,
                  onPressed: onDismiss,
                  tooltip:
                      dismissTooltip ??
                      AppLocalizations.of(context).bannerDismiss,
                  icon: const Icon(UfIcons.x),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
