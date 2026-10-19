// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../loquet/line_bank.dart';
import '../../loquet/loquet_pose.dart';
import '../../loquet/loquet_spot.dart';
import '../orgs/create_org_dialog.dart';
import '../orgs/join_org_dialog.dart';
import 'tree_panel.dart';

/// A section screen that replaces the sessions while the sidebar stays; all but settings follow the vault.
enum ShellPage { snippets, keychain, members, activity, trash, settings }

/// The single sidebar: vault selector, search and host tree of that vault, the « Dans [vault] » entries, then
/// Loquet with the account, Réglages and Verrouiller.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.tree,
    required this.page,
    required this.onShow,
    required this.onLock,
  });

  /// The search and the host tree of the selected vault.
  final TreePanel tree;

  /// The open section; null while the sessions show.
  final ShellPage? page;
  final ValueChanged<ShellPage?> onShow;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final colors = UfColors.of(context);
    final org = selectedOrg(state);
    final confirmed = org != null && org.status == 'confirmed';
    final vault = state.vault;
    final empty = !(vault?.entries ?? const []).any(
      (e) =>
          e.orgId == org?.id &&
          e.kind == ItemKind.host &&
          !vault!.isTrashed(e.id),
    );
    final pages = [
      ShellPage.snippets,
      ShellPage.keychain,
      if (confirmed) ShellPage.members,
      if (state.serverHas('audit')) ShellPage.activity,
      ShellPage.trash,
    ];
    return Container(
      key: const Key('sidebar'),
      decoration: BoxDecoration(
        color: colors.side,
        border: Border(right: BorderSide(color: colors.line)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          VaultSelector(onPicked: () => onShow(null)),
          Expanded(child: tree),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.line)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 1,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                    child: Text(
                      l.sidebarIn(org?.name ?? l.vaultPersonal),
                      style: Theme.of(context).textTheme.labelSmall!
                          .copyWith(color: colors.muted),
                    ),
                  ),
                  for (final p in pages)
                    SidebarEntry(
                      key: Key('section-${p.name}'),
                      icon: pageIcon(p),
                      label: pageTitle(l, p),
                      current: page == p,
                      onTap: () => onShow(page == p ? null : p),
                    ),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.line)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 0, 0),
              child: Row(
                spacing: 2,
                children: [
                  Expanded(
                    child: LoquetSpot(
                      key: const Key('loquet-spot-sidebar'),
                      placement: LoquetPlacement.sidebar,
                      name: state.accountName,
                      // an empty vault gives him its line
                      mood: empty ? LoquetMood.idle : null,
                      line: empty ? LineKey.emptyVault : null,
                    ),
                  ),
                  IconButton(
                    key: const Key('sidebar-settings'),
                    tooltip: l.railSettings,
                    isSelected: page == ShellPage.settings,
                    onPressed: () => onShow(
                      page == ShellPage.settings ? null : ShellPage.settings,
                    ),
                    icon: const Icon(UfIcons.gear),
                  ),
                  IconButton(
                    key: const Key('sidebar-lock'),
                    tooltip: l.railLock,
                    onPressed: onLock,
                    icon: const Icon(UfIcons.lock),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The org the sidebar shows, or null for the personal vault.
OrgSummary? selectedOrg(AppState state) {
  final orgs = state.serverHas('orgs') ? state.orgs : null;
  final id = orgs?.selected;
  return orgs?.orgs.where((o) => o.id == id).firstOrNull;
}

String pageTitle(AppLocalizations l, ShellPage page) => switch (page) {
  ShellPage.snippets => l.snippetsTitle,
  ShellPage.keychain => l.railKeychain,
  ShellPage.members => l.sectionMembers,
  ShellPage.activity => l.railActivity,
  ShellPage.trash => l.railTrash,
  ShellPage.settings => l.railSettings,
};

IconData pageIcon(ShellPage page) => switch (page) {
  ShellPage.snippets => UfIcons.terminal,
  ShellPage.keychain => UfIcons.key,
  ShellPage.members => UfIcons.users,
  ShellPage.activity => UfIcons.pulse,
  ShellPage.trash => UfIcons.trash,
  ShellPage.settings => UfIcons.gear,
};

/// A « Dans [vault] » entry: icon and label, the current one on `panelHover` in 600.
class SidebarEntry extends StatelessWidget {
  const SidebarEntry({
    super.key,
    required this.icon,
    required this.label,
    required this.current,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: 13.5,
      fontWeight: current ? FontWeight.w600 : FontWeight.w400,
    );
    return Semantics(
      selected: current,
      button: true,
      child: Material(
        color: current ? colors.panelHover : Colors.transparent,
        borderRadius: UfRadius.control,
        child: InkWell(
          borderRadius: UfRadius.control,
          hoverColor: colors.panelHover,
          onTap: onTap,
          child: SizedBox(
            height: UfHeight.medium,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                spacing: 10,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: current ? colors.text : colors.muted,
                  ),
                  Expanded(child: Text(label, style: style)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The selected vault with its role or host count; its menu lists every vault, then create and join.
class VaultSelector extends StatelessWidget {
  const VaultSelector({super.key, required this.onPicked});

  /// After a vault is picked: the sessions show again.
  final VoidCallback onPicked;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final colors = UfColors.of(context);
    final orgs = state.serverHas('orgs') ? state.orgs : null;
    final current = selectedOrg(state);
    final text = Theme.of(context).textTheme;
    final hosts = (state.vault?.entries ?? const [])
        .where(
          (e) =>
              e.orgId == null &&
              e.kind == ItemKind.host &&
              !state.vault!.isTrashed(e.id),
        )
        .length;
    String role(OrgSummary o) => switch (o.role) {
      'owner' => l.roleOwner,
      'admin' => l.roleAdmin,
      _ => l.roleMember,
    };
    void pick(String? orgId) {
      orgs?.select(orgId);
      onPicked();
    }

    Widget item({
      required Key key,
      required String name,
      required String subtitle,
      required bool selected,
      required VoidCallback? onPressed,
      required Widget tile,
    }) => MenuItemButton(
      key: key,
      onPressed: onPressed,
      leadingIcon: tile,
      trailingIcon: selected
          ? Icon(UfIcons.check, size: 14, color: colors.accentText)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name),
            Text(
              subtitle,
              style: text.bodySmall!.copyWith(color: colors.muted),
            ),
          ],
        ),
      ),
    );

    final name = current?.name ?? l.vaultPersonal;
    final subtitle = current == null
        ? l.vaultPersonalSubtitle(hosts)
        : current.status == 'confirmed'
        ? l.vaultOrgSubtitle(role(current))
        : l.orgAwaiting;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        minimumSize: const WidgetStatePropertyAll(Size(252, 0)),
        shadowColor: WidgetStatePropertyAll(colors.scrim),
      ),
      menuChildren: [
        item(
          key: const Key('vault-personal'),
          name: l.vaultPersonal,
          subtitle: l.vaultPersonalSubtitle(hosts),
          selected: current == null,
          onPressed: () => pick(null),
          tile: VaultTile(letter: l.vaultPersonal, personal: true),
        ),
        for (final org in orgs?.orgs ?? const <OrgSummary>[])
          item(
            key: Key('vault-org-${org.id}'),
            name: org.name,
            subtitle: org.status == 'confirmed'
                ? l.vaultOrgSubtitle(role(org))
                : l.orgAwaiting,
            selected: current?.id == org.id,
            onPressed: () => pick(org.id),
            tile: VaultTile(
              letter: org.name,
              awaiting: org.status != 'confirmed',
            ),
          ),
        if (orgs != null) ...[
          const Divider(height: 9),
          MenuItemButton(
            key: const Key('vault-new-org'),
            leadingIcon: const Icon(UfIcons.plus, size: 16),
            onPressed: () =>
                showUfDialog<void>(context, (_) => const CreateOrgDialog()),
            child: Text(l.railNewOrg),
          ),
          MenuItemButton(
            key: const Key('vault-join-org'),
            leadingIcon: const Icon(UfIcons.signIn, size: 16),
            onPressed: () =>
                showUfDialog<void>(context, (_) => const JoinOrgDialog()),
            child: Text(l.railJoinOrg),
          ),
        ],
      ],
      builder: (context, menu, _) => Semantics(
        button: true,
        label: l.sidebarVaults,
        child: Material(
          color: colors.panel,
          shape: RoundedRectangleBorder(
            borderRadius: UfRadius.card,
            side: BorderSide(color: menu.isOpen ? colors.edge : colors.line),
          ),
          child: InkWell(
            key: const Key('vault-selector'),
            borderRadius: UfRadius.card,
            hoverColor: Colors.transparent,
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  spacing: 10,
                  children: [
                    VaultTile(
                      letter: name,
                      personal: current == null,
                      awaiting:
                          current != null && current.status != 'confirmed',
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelLarge!.copyWith(fontSize: 13.5),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall!.copyWith(
                              color: colors.muted,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(UfIcons.caretUpDown, size: 14, color: colors.muted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A vault's first letter on a 28 px tile: `accent` for an org, `neutral` for the personal vault, an edge only
/// while the org awaits confirmation.
class VaultTile extends StatelessWidget {
  const VaultTile({
    super.key,
    required this.letter,
    this.personal = false,
    this.awaiting = false,
  });

  final String letter;
  final bool personal;
  final bool awaiting;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final (fill, ink) = awaiting
        ? (Colors.transparent, colors.muted)
        : personal
        ? (colors.neutral, colors.text)
        : (colors.accent, colors.accentFg);
    return AnimatedContainer(
      duration: UfMotion.of(context).fast,
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: UfRadius.control,
        border: awaiting ? Border.all(color: colors.edge) : null,
      ),
      child: Text(
        String.fromCharCode(letter.runes.first).toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: ink),
      ),
    );
  }
}
