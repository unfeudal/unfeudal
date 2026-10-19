// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';

/// A screen that replaces the tree and terminals while the rail stays.
enum ShellPage { keychain, devices, settings }

/// The 60 px rail: the personal vault pill, then keychain, devices, settings and lock at the bottom.
class VaultRail extends StatelessWidget {
  const VaultRail({
    super.key,
    required this.onLock,
    required this.onShow,
    this.page,
  });

  final VoidCallback onLock;

  /// The open management screen; null while the vault is shown.
  final ShellPage? page;

  /// Opens a management screen, or the vault for null.
  final ValueChanged<ShellPage?> onShow;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final motion = UfMotion.of(context);
    final inVault = page == null;

    /// A null [target] is the lock button.
    Widget item(ShellPage? target, String tooltip, IconData icon) {
      final onPressed = target == null ? onLock : () => onShow(target);
      final active = target != null && target == page;
      return Tooltip(
        message: tooltip,
        child: Material(
          color: active ? colors.select : Colors.transparent,
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(10)),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 38,
              child: Icon(
                icon,
                size: 19,
                color: active ? colors.accent : colors.muted,
                semanticLabel: tooltip,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: const Key('vault-rail'),
      width: 60,
      color: colors.rail,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        spacing: 10,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              SizedBox(width: 60, height: 38),
              AnimatedPositioned(
                duration: motion.base,
                curve: UfMotion.curve,
                left: 0,
                top: inVault ? 9 : 19,
                child: AnimatedContainer(
                  duration: motion.base,
                  curve: UfMotion.curve,
                  width: 4,
                  height: inVault ? 20 : 0,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(2),
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: l.vaultPersonal,
                child: GestureDetector(
                  onTap: () => onShow(null),
                  child: AnimatedContainer(
                    duration: motion.base,
                    curve: UfMotion.curve,
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: inVault ? colors.accentBg : colors.field,
                      borderRadius: BorderRadius.circular(inVault ? 12 : 19),
                    ),
                    child: Text(
                      String.fromCharCode(l.vaultPersonal.runes.first),
                      style: TextStyle(
                        fontFamily: 'Alegreya',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: inVault ? colors.accentFg : colors.text,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          item(ShellPage.keychain, l.railKeychain, UfIcons.key),
          item(ShellPage.devices, l.railDevices, UfIcons.devices),
          item(ShellPage.settings, l.railSettings, UfIcons.gear),
          item(null, l.railLock, UfIcons.lock),
        ],
      ),
    );
  }
}
