// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/rows.dart';
import '../../design/tokens.dart';
import '../../loquet/line_bank.dart';
import '../../loquet/loquet_pose.dart';
import '../../loquet/loquet_spot.dart';
import '../orgs/create_org_dialog.dart';
import '../orgs/join_org_dialog.dart';
import 'shortcuts.dart';
import 'tree_panel.dart';

part 'vault_selector.dart';
part 'vault_trigger.dart';

/// A section screen that replaces the sessions while the sidebar stays; all but settings follow the vault.
enum ShellPage { snippets, keychain, members, activity, trash, settings }

/// The single sidebar: vault selector, search and host tree of that vault, the entries of that vault's
/// sections, then Loquet with the account, Settings and Lock.
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
    final colors = UfColors.of(context);
    final divider = BoxDecoration(
      border: Border(top: BorderSide(color: colors.line)),
    );
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
            decoration: divider,
            child: _SectionEntries(page: page, onShow: onShow),
          ),
          DecoratedBox(
            decoration: divider,
            child: _SidebarFooter(page: page, onShow: onShow, onLock: onLock),
          ),
        ],
      ),
    );
  }
}

// The vault's sections under the vault name; members once the org is confirmed, activity when the server audits.
class _SectionEntries extends StatelessWidget {
  const _SectionEntries({required this.page, required this.onShow});

  final ShellPage? page;
  final ValueChanged<ShellPage?> onShow;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final colors = UfColors.of(context);
    final org = selectedOrg(state);
    final confirmed = org != null && org.isConfirmed;
    final pages = [
      ShellPage.snippets,
      ShellPage.keychain,
      if (confirmed) ShellPage.members,
      if (state.serverInfo.has(Flag.audit)) ShellPage.activity,
      ShellPage.trash,
    ];
    return Padding(
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
    );
  }
}

// Loquet with the account name, then Settings and Lock.
class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.page,
    required this.onShow,
    required this.onLock,
  });

  final ShellPage? page;
  final ValueChanged<ShellPage?> onShow;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final org = selectedOrg(state);
    final vault = state.vault;
    final empty = !(vault?.entries ?? const []).any(
      (e) =>
          e.orgId == org?.id &&
          e.kind == ItemKind.host &&
          !vault!.isTrashed(e.id),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 0, 0),
      child: Row(
        spacing: 2,
        children: [
          Expanded(
            child: LoquetSpot(
              key: const Key('loquet-spot-sidebar'),
              placement: LoquetPlacement.sidebar,
              name: state.displayName,
              // an empty vault gives him its line
              mood: empty ? LoquetMood.idle : null,
              line: empty ? LineKey.emptyVault : null,
            ),
          ),
          IconButton(
            key: const Key('sidebar-settings'),
            tooltip: l.railSettings,
            isSelected: page == ShellPage.settings,
            onPressed: () =>
                onShow(page == ShellPage.settings ? null : ShellPage.settings),
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
    );
  }
}

/// The org the sidebar shows, or null for the personal vault.
OrgSummary? selectedOrg(AppState state) {
  final orgs = state.serverInfo.has(Flag.orgs) ? state.orgs : null;
  return orgs?.byId(orgs.selected);
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

/// An entry of the vault's own sections: icon and label, the current one on `panelHover` in 600.
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
      child: UfFocusRing(
        child: Material(
          color: current ? colors.panelHover : Colors.transparent,
          borderRadius: UfRadius.control,
          child: InkWell(
            borderRadius: UfRadius.control,
            hoverColor: colors.panelHover,
            hoverDuration: UfMotion.of(context).fast,
            onTap: onTap,
            child: SizedBox(
              height: 30,
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
      ),
    );
  }
}
