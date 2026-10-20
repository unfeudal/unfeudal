// SPDX-License-Identifier: Apache-2.0
part of 'sidebar.dart';

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
    final current = selectedOrg(state);
    final name = current?.name ?? l.vaultPersonal;
    final subtitle = current == null
        ? l.vaultPersonalSubtitle(_hostsIn(state, null))
        : current.isConfirmed
        ? l.vaultOrgSubtitle(_roleLabel(l, current))
        : l.orgAwaiting;
    return LayoutBuilder(
      builder: (context, box) => MenuAnchor(
        alignmentOffset: const Offset(0, 4),
        style: MenuStyle(
          minimumSize: WidgetStatePropertyAll(Size(box.maxWidth, 0)),
          maximumSize: WidgetStatePropertyAll(Size(box.maxWidth, 480)),
          shadowColor: WidgetStatePropertyAll(colors.scrim),
        ),
        // the menu is as wide as the selector
        menuChildren: _menuRows(context, state, rowWidth: box.maxWidth - 8),
        builder: (context, menu, _) => _VaultTrigger(
          menu: menu,
          name: name,
          subtitle: subtitle,
          current: current,
        ),
      ),
    );
  }

  // Every vault, the personal one first, then create and join while the server has orgs.
  List<Widget> _menuRows(
    BuildContext context,
    AppState state, {
    required double rowWidth,
  }) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final orgs = state.serverInfo.has(Flag.orgs) ? state.orgs : null;
    final current = selectedOrg(state);
    void pick(String? orgId) {
      orgs?.select(orgId);
      onPicked();
    }

    return [
      _VaultMenuItem(
        index: 0,
        width: rowWidth,
        buttonKey: const Key('vault-personal'),
        name: l.vaultPersonal,
        subtitle: l.vaultMenuHosts(_hostsIn(state, null)),
        selected: current == null,
        onPressed: () => pick(null),
        tile: VaultTile(letter: l.vaultPersonal, personal: true),
      ),
      for (final (i, org) in (orgs?.orgs ?? const <OrgSummary>[]).indexed)
        _VaultMenuItem(
          index: i + 1,
          width: rowWidth,
          buttonKey: Key('vault-org-${org.id}'),
          name: org.name,
          subtitle: org.isConfirmed
              ? l.vaultMenuOrgHosts(_roleLabel(l, org), _hostsIn(state, org.id))
              : l.orgAwaiting,
          selected: current?.id == org.id,
          dim: !org.isConfirmed,
          onPressed: () => pick(org.id),
          tile: VaultTile(letter: org.name, awaiting: !org.isConfirmed),
        ),
      if (orgs != null) ...[
        Container(
          width: rowWidth,
          height: 1,
          margin: const EdgeInsets.all(4),
          color: colors.line,
        ),
        _VaultMenuAction(
          width: rowWidth,
          buttonKey: const Key('vault-new-org'),
          icon: UfIcons.plus,
          label: l.railNewOrg,
          onTap: () =>
              showUfDialog<void>(context, (_) => const CreateOrgDialog()),
        ),
        _VaultMenuAction(
          width: rowWidth,
          buttonKey: const Key('vault-join-org'),
          icon: UfIcons.signIn,
          label: l.railJoinOrg,
          onTap: () =>
              showUfDialog<void>(context, (_) => const JoinOrgDialog()),
        ),
      ],
    ];
  }
}

int _hostsIn(AppState state, String? orgId) =>
    (state.vault?.entries ?? const [])
        .where(
          (e) =>
              e.orgId == orgId &&
              e.kind == ItemKind.host &&
              !state.vault!.isTrashed(e.id),
        )
        .length;

String _roleLabel(AppLocalizations l, OrgSummary org) => switch (org.role) {
  'owner' => l.roleOwner,
  'admin' => l.roleAdmin,
  _ => l.roleMember,
};

// Vault rows hold two lines: 32 px minimum, 4/8 padding over the themed 30 px row.
const _menuRowStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(0, 32)),
  padding: WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  ),
);

Widget _menuRow({
  required bool first,
  required double width,
  required Widget child,
}) => Padding(
  padding: EdgeInsets.only(top: first ? 0 : 1),
  child: SizedBox(width: width, child: child),
);

// A vault of the menu: its tile, name and subtitle, then a check when selected or its shortcut.
class _VaultMenuItem extends StatelessWidget {
  const _VaultMenuItem({
    required this.index,
    required this.width,
    required this.buttonKey,
    required this.name,
    required this.subtitle,
    required this.selected,
    required this.onPressed,
    required this.tile,
    this.dim = false,
  });

  final int index;
  final double width;
  final Key buttonKey;
  final String name;
  final String subtitle;
  final bool selected;
  final VoidCallback? onPressed;
  final Widget tile;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    return _menuRow(
      first: index == 0,
      width: width,
      child: MenuItemButton(
        key: buttonKey,
        onPressed: onPressed,
        style: _menuRowStyle,
        overflowAxis: Axis.vertical,
        leadingIcon: tile,
        trailingIcon: selected
            ? Icon(UfIcons.check, size: 14, color: colors.accentText)
            : index < 9
            ? Text(
                UfShortcuts.vaultLabel(index + 1),
                style: monoStyle.copyWith(fontSize: 11, color: colors.muted),
              )
            : null,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 2, end: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: dim ? TextStyle(color: colors.muted) : null),
              Text(
                subtitle,
                style: text.bodySmall!.copyWith(
                  fontSize: 12,
                  color: colors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// An action row keeps its glyph in a 28 px slot, aligned with the vault tiles.
class _VaultMenuAction extends StatelessWidget {
  const _VaultMenuAction({
    required this.width,
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final double width;
  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _menuRow(
    first: false,
    width: width,
    child: MenuItemButton(
      key: buttonKey,
      style: _menuRowStyle,
      leadingIcon: SizedBox.square(
        dimension: 28,
        child: Icon(icon, size: 16, color: UfColors.of(context).muted),
      ),
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 2),
        child: Text(label),
      ),
    ),
  );
}
