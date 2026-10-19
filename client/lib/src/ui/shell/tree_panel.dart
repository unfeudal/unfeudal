// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/empty_state.dart';
import '../../design/icons.dart';
import '../../design/seal.dart';
import '../../design/tokens.dart';
import '../../loquet/line_bank.dart';
import '../../loquet/loquet_pose.dart';
import '../../loquet/loquet_spot.dart';
import '../../vault/vault.dart';
import '../orgs/acl_editor.dart';
import '../orgs/members_screen.dart';
import '../orgs/org_settings_screen.dart';
import '../orgs/teams_screen.dart';
import '../orgs/why_rights_view.dart';
import 'shortcuts.dart';

/// The selected vault (personal or an org) as a tree of folders and hosts, with a search over name, address and tags.
class TreePanel extends StatefulWidget {
  const TreePanel({
    super.key,
    required this.searchFocus,
    this.onNewHost,
    this.onNewFolder,
    this.onEdit,
    this.onHide,
  });

  final FocusNode searchFocus;

  /// Null keeps the button disabled; both are disabled while the server is read-only.
  final VoidCallback? onNewHost;
  final VoidCallback? onNewFolder;

  /// Opens the editor of a host or folder (the pencil of its row).
  final void Function(VaultEntry entry)? onEdit;

  /// Hides the panel (the same as Ctrl+Shift+B).
  final VoidCallback? onHide;

  @override
  State<TreePanel> createState() => _TreePanelState();
}

class _TreePanelState extends State<TreePanel> {
  final _query = TextEditingController();
  final _collapsed = <String>{};
  ({String id, DateTime at})? _lastTap;

  /// The row the last click selected: highlighted, with its address and pencil.
  String? _selected;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final colors = UfColors.of(context);
    final vault = state.vault;
    final readOnly = state.sync?.readOnly ?? true;
    final orgs = state.orgs;
    final orgId = orgs?.selected;
    final org = orgs?.orgs.where((o) => o.id == orgId).firstOrNull;
    final awaiting = org != null && org.status != 'confirmed';
    final online = state.sync?.online ?? false;
    // an org vault: folders need the server, and both buttons need edit somewhere in the cached block
    final orgEdit =
        org == null ||
        orgs!.isAdmin(org.id) ||
        (orgs.block?.folderTree ?? const <FolderNode>[]).any(
          (n) =>
              n.orgId == org.id &&
              orgs.permissions(org.id, n.folderId).contains(Permission.edit),
        );
    final visible = [
      for (final e in vault?.entries ?? const <VaultEntry>[])
        if (e.orgId == orgId && !vault!.isTrashed(e.id) && _shown(e)) e,
    ];
    final query = _query.text.trim().toLowerCase();
    final rows = query.isEmpty
        ? _tree(context, state, visible)
        : [
            for (final e in visible)
              if (e.kind == ItemKind.host && _matches(e, query))
                _row(context, state, e, depth: 0),
          ];
    final text = Theme.of(context).textTheme;
    return Container(
      color: colors.side,
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        org?.name ?? l.vaultPersonal,
                        style: text.headlineSmall,
                      ),
                      if (org == null)
                        Text(
                          l.treeRolePersonal,
                          style: text.labelSmall!.copyWith(
                            color: colors.muted,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                ),
                if (org != null && !awaiting)
                  PopupMenuButton<Widget Function()>(
                    key: const Key('org-menu'),
                    tooltip: l.orgMenu,
                    icon: const Icon(UfIcons.users, size: 17),
                    onSelected: (screen) => _push(context, screen()),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        key: const Key('org-menu-members'),
                        value: () => MembersScreen(orgId: org.id),
                        child: Text(l.membersTitle),
                      ),
                      if (state.serverHas('teams') && orgs!.isAdmin(org.id))
                        PopupMenuItem(
                          key: const Key('org-menu-teams'),
                          value: () => TeamsScreen(orgId: org.id),
                          child: Text(l.teamsTitle),
                        ),
                      if (orgs!.isAdmin(org.id))
                        PopupMenuItem(
                          key: const Key('org-menu-settings'),
                          value: () => OrgSettingsScreen(orgId: org.id),
                          child: Text(l.orgSettingsTitle),
                        ),
                    ],
                  ),
                IconButton(
                  key: const Key('tree-hide'),
                  tooltip: l.treeHide,
                  iconSize: 17,
                  onPressed: widget.onHide,
                  icon: const Icon(UfIcons.sidebarSimple),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: TextField(
              key: const Key('tree-search'),
              controller: _query,
              focusNode: widget.searchFocus,
              onChanged: (q) {
                setState(() {});
                state.loquet.watch((q.length / 30).clamp(0, 1));
              },
              decoration: InputDecoration(
                hintText: l.treeSearch(
                  UfShortcuts.label(UfShortcut.focusSearch),
                ),
                prefixIcon: const Icon(UfIcons.magnifyingGlass, size: 16),
                prefixIconConstraints: const BoxConstraints(minWidth: 36),
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
              ),
            ),
          ),
          Expanded(
            child: awaiting
                ? Column(
                    children: [
                      Expanded(
                        child: EmptyState(title: org.name, body: l.orgAwaiting),
                      ),
                      TextButton(
                        key: const Key('org-awaiting-leave'),
                        onPressed: () =>
                            confirmAndLeaveOrg(context, org.id, org.name),
                        child: Text(l.orgLeave),
                      ),
                      const SizedBox(height: 12),
                    ],
                  )
                : rows.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        l.treeEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.muted),
                      ),
                    ),
                  )
                : ListView(children: rows),
          ),
          // the tree's empty states give their face and line to the card instead of a second Loquet
          Padding(
            key: const Key('loquet-spot-tree'),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: LoquetSpot(
              placement: LoquetPlacement.tree,
              mood: rows.isNotEmpty
                  ? null
                  : query.isEmpty
                  ? LoquetMood.idle
                  : LoquetMood.search,
              line: rows.isNotEmpty
                  ? null
                  : query.isEmpty
                  ? LineKey.emptyVault
                  : LineKey.emptySearch,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 6,
              children: [
                FilledButton.icon(
                  key: const Key('tree-new-host'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: readOnly || !orgEdit || awaiting
                      ? null
                      : widget.onNewHost,
                  icon: const Icon(UfIcons.plus, size: 15),
                  label: Text(l.treeNewHost),
                ),
                Tooltip(
                  message: org != null && !online ? l.treeNewFolderOnline : '',
                  child: TextButton.icon(
                    key: const Key('tree-new-folder'),
                    onPressed:
                        readOnly ||
                            !orgEdit ||
                            awaiting ||
                            (org != null && !online)
                        ? null
                        : widget.onNewFolder,
                    icon: const Icon(UfIcons.folderSimplePlus, size: 15),
                    label: Text(l.treeNewFolder),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Org screens open over the shell; their back arrow pops them.
  static void _push(BuildContext context, Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));

  /// Hosts, folders, and the entries the tree must label (unreadable, newer type).
  static bool _shown(VaultEntry e) =>
      e.kind == ItemKind.host ||
      e.kind == ItemKind.folder ||
      e.state == EntryState.unsupported;

  static bool _matches(VaultEntry e, String query) {
    final meta = e.meta ?? const {};
    final texts = [
      meta['name'],
      meta['address'],
      ...switch (meta['tags']) {
        final List<Object?> tags => tags,
        _ => const [],
      },
    ];
    return texts.whereType<String>().any(
      (t) => t.toLowerCase().contains(query),
    );
  }

  /// Folders nested under their parent (a stored loop is cut by the seen-set); orphans at the root.
  List<Widget> _tree(
    BuildContext context,
    AppState state,
    List<VaultEntry> visible,
  ) {
    final folders = {
      for (final e in visible)
        if (e.kind == ItemKind.folder && e.state == EntryState.ok) e.id: e,
    };
    final children = <String?, List<VaultEntry>>{};
    for (final e in visible) {
      final parent = folders.containsKey(e.folderId) ? e.folderId : null;
      (children[parent] ??= []).add(e);
    }
    final out = <Widget>[];
    final seen = <String>{};
    void walk(String? parent, int depth) {
      final items = [...?children[parent]]
        ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
      for (final e in items.where(
        (e) => e.kind == ItemKind.folder && folders.containsKey(e.id),
      )) {
        if (!seen.add(e.id)) continue;
        final open = !_collapsed.contains(e.id);
        final hosts = (children[e.id] ?? const <VaultEntry>[])
            .where((c) => c.kind == ItemKind.host)
            .length;
        out.add(_folderRow(context, e, depth, open, hosts));
        if (open) walk(e.id, depth + 1);
      }
      for (final e in items.where(
        (e) => !(e.kind == ItemKind.folder && folders.containsKey(e.id)),
      )) {
        out.add(_row(context, state, e, depth: depth));
      }
    }

    walk(null, 0);
    return out;
  }

  Widget _editButton(BuildContext context, VaultEntry e) => IconButton(
    key: Key('edit-${e.id}'),
    tooltip: AppLocalizations.of(context).itemEdit,
    visualDensity: VisualDensity.compact,
    iconSize: 15,
    color: UfColors.of(context).accent,
    onPressed: widget.onEdit == null ? null : () => widget.onEdit!(e),
    icon: const Icon(UfIcons.pencil),
  );

  /// Access (with manage) and why, for an org folder.
  List<Widget> _orgFolderButtons(BuildContext context, VaultEntry e) {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final orgId = e.orgId!;
    final manage = state.orgs!
        .permissions(orgId, e.id)
        .contains(Permission.manage);
    Widget button(String key, String tooltip, IconData icon, Widget screen) =>
        IconButton(
          key: Key(key),
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          iconSize: 15,
          onPressed: () => _push(context, screen),
          icon: Icon(icon),
        );
    return [
      if (manage)
        button(
          'folder-access-${e.id}',
          l.aclTitle(e.name ?? ''),
          UfIcons.users,
          AclEditor(orgId: orgId, folderId: e.id),
        ),
      button(
        'folder-why-${e.id}',
        l.whyTitle,
        UfIcons.info,
        WhyRightsView(
          orgId: orgId,
          folderId: e.id,
          userId: state.stored!.userId,
        ),
      ),
    ];
  }

  Widget _folderRow(
    BuildContext context,
    VaultEntry e,
    int depth,
    bool open,
    int hosts,
  ) {
    final colors = UfColors.of(context);
    final selected = _selected == e.id;
    final style = Theme.of(context).textTheme.labelSmall!
        .copyWith(color: colors.muted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Material(
        color: selected ? colors.select : Colors.transparent,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        child: InkWell(
          key: Key('folder-${e.id}'),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          onTap: () => setState(() {
            _selected = e.id;
            open ? _collapsed.add(e.id) : _collapsed.remove(e.id);
          }),
          child: Padding(
            padding: EdgeInsets.fromLTRB(8.0 + depth * 14, 4, 6, 4),
            child: Row(
              spacing: 6,
              children: [
                Icon(
                  open ? UfIcons.caretDown : UfIcons.caretRight,
                  size: 12,
                  color: colors.muted,
                ),
                Expanded(child: Text(e.name ?? '', style: style)),
                if (selected && e.orgId != null)
                  ..._orgFolderButtons(context, e),
                if (selected)
                  _editButton(context, e)
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '$hosts',
                      style: style.copyWith(fontWeight: FontWeight.w400),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AppState state,
    VaultEntry e, {
    required int depth,
  }) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final padding = EdgeInsets.fromLTRB(22.0 + depth * 14, 7, 6, 7);
    final muted = TextStyle(color: colors.muted);
    if (e.state == EntryState.unreadable || e.state == EntryState.unsupported) {
      return Padding(
        key: Key('host-${e.id}'),
        padding: padding,
        child: Text(
          e.awaitingKey
              ? l.treeAwaitingKey
              : e.state == EntryState.unreadable
              ? l.treeUnreadable
              : l.treeUnsupported,
          style: muted.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }
    void connect() => state.connect(e.id);
    final notes = [
      if (e.state == EntryState.readOnly) l.treeReadOnly,
      if (e.pending) l.treePending,
    ];
    final selected = _selected == e.id;
    final lookup = selected ? state.vault?.hostLookup(e.id) : null;
    final target = switch (lookup) {
      (:final meta, :final resolved, org: _) => [
        if (resolved.user case final user?) '$user@',
        meta.address,
        if (resolved.port != 22) ':${resolved.port}',
      ].join(),
      null => null,
    };
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): connect},
      child: Focus(
        child: Builder(
          builder: (row) => Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Material(
              color: selected ? colors.select : Colors.transparent,
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              child: InkWell(
                key: Key('host-${e.id}'),
                borderRadius: const BorderRadius.all(Radius.circular(8)),
                // a click selects the row (its own focus node, so Enter connects); a second one in time connects.
                // Detected here: onDoubleTap would hold back onTap and leave a timer behind every click
                onTap: () {
                  Focus.of(row).requestFocus();
                  setState(() => _selected = e.id);
                  final now = DateTime.now();
                  final last = _lastTap;
                  if (last != null &&
                      last.id == e.id &&
                      now.difference(last.at) < kDoubleTapTimeout) {
                    _lastTap = null;
                    connect();
                  } else {
                    _lastTap = (id: e.id, at: now);
                  }
                },
                child: Padding(
                  padding: padding,
                  child: Row(
                    spacing: 10,
                    children: [
                      Seal(state: state.sealFor(e.id)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.name ?? '',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                            if (target != null)
                              Text(
                                target,
                                overflow: TextOverflow.ellipsis,
                                style: muted.copyWith(fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      if (notes.isNotEmpty)
                        Flexible(
                          child: Text(
                            notes.join(', '),
                            style: muted.copyWith(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (selected) _editButton(context, e),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
