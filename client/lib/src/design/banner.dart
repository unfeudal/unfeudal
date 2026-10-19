// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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
      BannerTone.info => (colors.accent, colors.infoSoft, UfIcons.info),
      BannerTone.warn => (colors.warn, colors.warnSoft, UfIcons.warning),
      BannerTone.danger => (
        colors.danger,
        colors.dangerSoft,
        UfIcons.warningOctagon,
      ),
    };
    const compact = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    return Material(
      color: fill,
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        child: Row(
          spacing: 12,
          children: [
            Icon(icon, color: color, size: 20),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(message),
              ),
            ),
            if (action case (final label, final onPressed))
              FilledButton(
                key: actionKey,
                style: FilledButton.styleFrom(padding: compact),
                onPressed: onPressed,
                child: Text(label),
              ),
            if (secondAction case (final label, final onPressed))
              TextButton(
                key: secondActionKey,
                style: TextButton.styleFrom(
                  foregroundColor: colors.text,
                  padding: compact,
                ),
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
                icon: const Icon(UfIcons.x, size: 16),
              ),
          ],
        ),
      ),
    );
  }
}
