// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../loquet/loquet_spot.dart';
import '../orgs/create_org_dialog.dart';
import '../orgs/join_org_dialog.dart';

/// A screen that replaces the tree and terminals while the rail stays.
enum ShellPage { keychain, activity, devices, admin, settings }

/// The 60 px rail: the personal vault pill, one pill per org, then keychain, devices, settings and lock at the bottom.
class VaultRail extends StatelessWidget {
  const VaultRail({
    super.key,
    required this.onLock,
    required this.onShow,
    this.page,
    this.showLoquet = false,
  });

  /// Set while the tree, and its Loquet, is hidden.
  final bool showLoquet;

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
    final state = AppScope.of(context);
    final orgs = state.serverHas('orgs') ? state.orgs : null;
    final selected = orgs?.selected;

    /// A null [target] is the lock button.
    Widget item(ShellPage? target, String tooltip, IconData icon, {Key? key}) {
      final onPressed = target == null ? onLock : () => onShow(target);
      final active = target != null && target == page;
      return Tooltip(
        key: key,
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

    /// A vault: its first letter, the accent bar when shown; a muted ring while the org awaits confirmation.
    Widget pill({
      required Key key,
      required String label,
      required bool active,
      required VoidCallback onTap,
      bool awaiting = false,
    }) => Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        const SizedBox(width: 60, height: 38),
        AnimatedPositioned(
          duration: motion.base,
          curve: UfMotion.curve,
          left: 0,
          top: active ? 9 : 19,
          child: AnimatedContainer(
            duration: motion.base,
            curve: UfMotion.curve,
            width: 4,
            height: active ? 20 : 0,
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(2),
              ),
            ),
          ),
        ),
        Tooltip(
          message: label,
          child: GestureDetector(
            key: key,
            onTap: onTap,
            child: AnimatedContainer(
              duration: motion.base,
              curve: UfMotion.curve,
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? colors.accentBg : colors.field,
                borderRadius: BorderRadius.circular(active ? 12 : 19),
                border: awaiting ? Border.all(color: colors.muted) : null,
              ),
              child: Text(
                String.fromCharCode(label.runes.first),
                style: TextStyle(
                  fontFamily: 'Alegreya',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: active ? colors.accentFg : colors.text,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    Widget action(Key key, String tooltip, IconData icon, VoidCallback onTap) =>
        Tooltip(
          message: tooltip,
          child: IconButton(
            key: key,
            iconSize: 17,
            color: colors.muted,
            onPressed: onTap,
            icon: Icon(icon, semanticLabel: tooltip),
          ),
        );

    return Container(
      key: const Key('vault-rail'),
      width: 60,
      color: colors.rail,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        spacing: 10,
        children: [
          pill(
            key: const Key('vault-personal'),
            label: l.vaultPersonal,
            active: inVault && selected == null,
            onTap: () {
              orgs?.select(null);
              onShow(null);
            },
          ),
          for (final org in orgs?.orgs ?? const <OrgSummary>[])
            pill(
              key: Key('vault-org-${org.id}'),
              label: org.name,
              active: inVault && selected == org.id,
              awaiting: org.status != 'confirmed',
              onTap: () {
                orgs!.select(org.id);
                onShow(null);
              },
            ),
          if (orgs != null) ...[
            action(
              const Key('rail-new-org'),
              l.railNewOrg,
              UfIcons.plus,
              () => showUfDialog<void>(context, (_) => const CreateOrgDialog()),
            ),
            action(
              const Key('rail-join-org'),
              l.railJoinOrg,
              UfIcons.link,
              () => showUfDialog<void>(context, (_) => const JoinOrgDialog()),
            ),
          ],
          const Spacer(),
          item(ShellPage.keychain, l.railKeychain, UfIcons.key),
          if (state.serverHas('audit'))
            item(
              ShellPage.activity,
              l.railActivity,
              UfIcons.clockCounterClockwise,
              key: const Key('rail-activity'),
            ),
          item(ShellPage.devices, l.railDevices, UfIcons.devices),
          if (state.stored?.isInstanceOwner ?? false)
            item(
              ShellPage.admin,
              l.railAdmin,
              UfIcons.shieldCheck,
              key: const Key('rail-admin'),
            ),
          item(ShellPage.settings, l.railSettings, UfIcons.gear),
          if (showLoquet)
            const LoquetSpot(
              key: Key('loquet-spot-rail'),
              placement: LoquetPlacement.rail,
            ),
          item(null, l.railLock, UfIcons.lock),
        ],
      ),
    );
  }
}
