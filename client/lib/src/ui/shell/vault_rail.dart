// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';

/// The 60 px rail: the personal vault pill, then keychain, devices, settings and lock at the bottom.
class VaultRail extends StatelessWidget {
  const VaultRail({
    super.key,
    required this.onLock,
    this.onKeychain,
    this.onDevices,
    this.onSettings,
  });

  final VoidCallback onLock;
  final VoidCallback? onKeychain;
  final VoidCallback? onDevices;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final motion = UfMotion.of(context);
    return Container(
      key: const Key('vault-rail'),
      width: 60,
      color: colors.rail,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              // active indicator bar
              Container(width: 3, height: 24, color: colors.accent),
              const SizedBox(width: 9),
              Tooltip(
                message: l.vaultPersonal,
                child: AnimatedContainer(
                  duration: motion.fast,
                  curve: UfMotion.curve,
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.accentBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    String.fromCharCode(l.vaultPersonal.runes.first),
                    style: TextStyle(
                      color: colors.accentFg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            tooltip: l.railKeychain,
            onPressed: onKeychain,
            icon: const Icon(UfIcons.key),
          ),
          IconButton(
            tooltip: l.railDevices,
            onPressed: onDevices,
            icon: const Icon(UfIcons.devices),
          ),
          IconButton(
            tooltip: l.railSettings,
            onPressed: onSettings,
            icon: const Icon(UfIcons.gear),
          ),
          IconButton(
            tooltip: l.railLock,
            onPressed: onLock,
            icon: const Icon(UfIcons.lock),
          ),
        ],
      ),
    );
  }
}
