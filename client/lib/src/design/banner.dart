// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'icons.dart';
import 'logo.dart';
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
  });

  final BannerTone tone;
  final String message;
  final (String, VoidCallback)? action;
  final (String, VoidCallback)? secondAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    // status never by colour alone: each tone has its own icon shape
    final (color, icon) = switch (tone) {
      BannerTone.info => (colors.accent, UfIcons.info),
      BannerTone.warn => (colors.warn, UfIcons.warning),
      BannerTone.danger => (colors.danger, UfIcons.warningOctagon),
    };
    return Material(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          spacing: 8,
          children: [
            IconTheme.merge(
              data: IconThemeData(color: color),
              child: const UfLogo(size: 40),
            ),
            Icon(icon, color: color, size: 20),
            Expanded(child: Text(message)),
            if (action case (final label, final onPressed))
              TextButton(onPressed: onPressed, child: Text(label)),
            if (secondAction case (final label, final onPressed))
              TextButton(onPressed: onPressed, child: Text(label)),
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                tooltip: AppLocalizations.of(context).bannerDismiss,
                icon: const Icon(UfIcons.x, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}
