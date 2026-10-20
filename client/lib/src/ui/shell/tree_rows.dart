// SPDX-License-Identifier: Apache-2.0
part of 'tree_panel.dart';

TextStyle _rowStyle(BuildContext context, bool selected) {
  final colors = UfColors.of(context);
  return Theme.of(context).textTheme.bodyMedium!.copyWith(
    fontSize: 13.5,
    height: 1.3,
    color: selected ? colors.accentText : colors.text,
    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
  );
}

Widget _unreadableRow(BuildContext context, VaultEntry e, EdgeInsets padding) {
  final l = AppLocalizations.of(context);
  final muted = Theme.of(context).textTheme.bodySmall!
      .copyWith(color: UfColors.of(context).muted);
  return Padding(
    key: Key('host-${e.id}'),
    padding: padding,
    child: Text(
      e.awaitingKey
          ? l.treeAwaitingKey
          : e.state == EntryState.unreadable
          ? l.treeUnreadable
          : l.treeUnsupported,
      style: muted.copyWith(fontSize: 13.5),
    ),
  );
}

// The Hosts label with the new host and new folder buttons; a null callback disables its button.
class _TreeHeader extends StatelessWidget {
  const _TreeHeader({
    required this.onNewHost,
    required this.onNewFolder,
    required this.newFolderBlocked,
  });

  final VoidCallback? onNewHost;
  final VoidCallback? onNewFolder;
  final bool newFolderBlocked;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 0, 0),
      child: Row(
        spacing: 2,
        children: [
          Expanded(
            child: Text(
              l.sidebarHosts,
              style: Theme.of(context).textTheme.labelSmall!
                  .copyWith(color: colors.muted),
            ),
          ),
          IconButton(
            key: const Key('tree-new-host'),
            tooltip: l.treeNewHost,
            onPressed: onNewHost,
            icon: const Icon(UfIcons.plus),
          ),
          IconButton(
            key: const Key('tree-new-folder'),
            tooltip: newFolderBlocked ? l.treeNewFolderOnline : l.treeNewFolder,
            onPressed: onNewFolder,
            icon: const Icon(UfIcons.folderSimplePlus),
          ),
        ],
      ),
    );
  }
}

// What fills the tree area: the leave offer of an org awaiting confirmation, the skeleton while loading, the
// empty notice, or the rows.
class _TreeBody extends StatelessWidget {
  const _TreeBody({
    required this.awaitingOrg,
    required this.loading,
    required this.rows,
  });

  final OrgSummary? awaitingOrg;
  final bool loading;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final muted = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: colors.muted);
    if (awaitingOrg case final org?) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(l.orgAwaiting, style: muted),
            TextButton(
              key: const Key('org-awaiting-leave'),
              style: dangerQuietStyle(colors).merge(smallButton),
              onPressed: () => confirmAndLeaveOrg(context, org.id, org.name),
              child: Text(l.orgLeave),
            ),
          ],
        ),
      );
    }
    if (loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: UfTreeSkeleton(),
      );
    }
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(l.treeEmpty, style: muted),
      );
    }
    return UfStagger(
      child: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) => UfStaggerItem(index: i, child: rows[i]),
      ),
    );
  }
}

// A host row's line: its seal, name over the target of a selected row, notes, the open-tab mark and the pencil.
class _HostLine extends StatelessWidget {
  const _HostLine({
    required this.seal,
    required this.name,
    required this.nameStyle,
    required this.target,
    required this.notes,
    required this.hasOpenTab,
    required this.editButton,
  });

  final SealState seal;
  final String name;
  final TextStyle nameStyle;
  final String? target;
  final List<String> notes;
  final bool hasOpenTab;
  final Widget? editButton;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return Row(
      spacing: 8,
      children: [
        Seal(state: seal),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, overflow: TextOverflow.ellipsis, style: nameStyle),
              if (target case final target?)
                Text(
                  target,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle.copyWith(fontSize: 11, color: colors.muted),
                ),
            ],
          ),
        ),
        if (notes.isNotEmpty) Flexible(child: UfTag(notes.join(', '))),
        if (hasOpenTab)
          Icon(
            UfIcons.terminalWindow,
            size: 14,
            color: colors.muted,
            semanticLabel: AppLocalizations.of(context).tabOpen,
          ),
        ?editButton,
      ],
    );
  }
}
