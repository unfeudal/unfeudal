// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/buttons.dart';
import '../../design/icons.dart';
import '../../design/rows.dart';
import '../../design/seal.dart';
import '../../design/tokens.dart';
import '../../events/app_events.dart';
import '../../terminal/snippet_insertion.dart';
import '../../vault/snippet_store.dart';
import '../../vault/vault.dart';
import '../terminal/multiline_dialog.dart';
import '../orgs/acl_editor.dart';
import '../orgs/members_screen.dart' show confirmAndLeaveOrg;
import '../orgs/why_rights_view.dart';
import 'shortcuts.dart';

/// The search and host tree of the selected vault (personal or an org); the search covers name, address and tags.
class TreePanel extends StatefulWidget {
  const TreePanel({
    super.key,
    required this.searchFocus,
    this.onNewHost,
    this.onNewFolder,
    this.onEdit,
  });

  final FocusNode searchFocus;

  /// Null keeps the button disabled; both are disabled while the server is read-only.
  final VoidCallback? onNewHost;
  final VoidCallback? onNewFolder;

  /// Opens the editor of a host or folder (the pencil of its row).
  /// [from] is the global rect of the control that asked: the editor grows out of it.
  final void Function(VaultEntry entry, Rect? from)? onEdit;

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
            ..._snippetResults(context, state, query, orgId),
          ];
    final text = Theme.of(context).textTheme;
    final newFolderBlocked = org != null && !online;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        TextField(
          key: const Key('tree-search'),
          controller: _query,
          focusNode: widget.searchFocus,
          style: text.bodyMedium!.copyWith(fontSize: 13.5),
          onChanged: (q) {
            setState(() {});
            state.loquet.watch((q.length / 30).clamp(0, 1));
          },
          decoration: InputDecoration(
            hintText: l.treeSearch(UfShortcuts.label(UfShortcut.focusSearch)),
            prefixIcon: Icon(
              UfIcons.magnifyingGlass,
              size: 14,
              color: colors.muted,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 32),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 0, 0),
          child: Row(
            spacing: 2,
            children: [
              Expanded(
                child: Text(
                  l.sidebarHosts,
                  style: text.labelSmall!.copyWith(color: colors.muted),
                ),
              ),
              IconButton(
                key: const Key('tree-new-host'),
                tooltip: l.treeNewHost,
                onPressed: readOnly || !orgEdit || awaiting
                    ? null
                    : widget.onNewHost,
                icon: const Icon(UfIcons.plus),
              ),
              IconButton(
                key: const Key('tree-new-folder'),
                tooltip: newFolderBlocked
                    ? l.treeNewFolderOnline
                    : l.treeNewFolder,
                onPressed: readOnly || !orgEdit || awaiting || newFolderBlocked
                    ? null
                    : widget.onNewFolder,
                icon: const Icon(UfIcons.folderSimplePlus),
              ),
            ],
          ),
        ),
        Expanded(
          child: awaiting
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      Text(
                        l.orgAwaiting,
                        style: text.bodySmall!.copyWith(color: colors.muted),
                      ),
                      TextButton(
                        key: const Key('org-awaiting-leave'),
                        style: dangerQuietStyle(colors).merge(smallButton),
                        onPressed: () =>
                            confirmAndLeaveOrg(context, org.id, org.name),
                        child: Text(l.orgLeave),
                      ),
                    ],
                  ),
                )
              : rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    query.isEmpty ? l.treeEmpty : l.searchNoResult,
                    style: text.bodySmall!.copyWith(color: colors.muted),
                  ),
                )
              : ListView(children: rows),
        ),
      ],
    );
  }

  /// Snippets of this vault and of the personal one matching [query], under their own heading; a click inserts
  /// one into the active session.
  List<Widget> _snippetResults(
    BuildContext context,
    AppState state,
    String query,
    String? orgId,
  ) {
    final vault = state.vault;
    if (vault == null) return const [];
    final found = [
      for (final s in SnippetStore(vault).list(query: query))
        if (vault.entry(s.id)?.orgId case final owner
            when owner == null || owner == orgId)
          s,
    ];
    if (found.isEmpty) return const [];
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final tab = state.tabs.isEmpty
        ? null
        : state.tabs[state.activeTab.clamp(0, state.tabs.length - 1)];
    final canInsert = tab?.state == SealState.connected;
    final text = Theme.of(context).textTheme;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
        child: Text(
          l.searchSnippets,
          style: text.labelSmall!.copyWith(color: colors.muted),
        ),
      ),
      for (final s in found)
        Tooltip(
          message: canInsert ? s.meta.command : l.snippetNoTerminal,
          child: InkWell(
            key: Key('search-snippet-${s.id}'),
            borderRadius: UfRadius.control,
            hoverColor: colors.panelHover,
            onTap: canInsert
                ? () async {
                    final sent = await insertSnippet(
                      tab!,
                      s.meta.command,
                      confirm: () => confirmUnsafeMultiline(context),
                    );
                    if (sent) state.emit(SnippetInserted(snippetId: s.id));
                  }
                : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: UfHeight.small),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                spacing: 8,
                children: [
                  Icon(UfIcons.terminal, size: 14, color: colors.muted),
                  Expanded(
                    child: Text(
                      s.meta.name,
                      overflow: TextOverflow.ellipsis,
                      style: _rowStyle(
                        context,
                        false,
                      ).copyWith(color: canInsert ? colors.text : colors.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
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

  Widget _editButton(BuildContext context, VaultEntry e) => Builder(
    builder: (button) => IconButton(
      key: Key('edit-${e.id}'),
      tooltip: AppLocalizations.of(context).itemEdit,
      onPressed: widget.onEdit == null
          ? null
          : () => widget.onEdit!(e, _globalRect(button)),
      icon: const Icon(UfIcons.pencil),
    ),
  );

  static Rect? _globalRect(BuildContext context) =>
      switch (context.findRenderObject()) {
        final RenderBox box when box.hasSize =>
          box.localToGlobal(Offset.zero) & box.size,
        _ => null,
      };

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
    final style = _rowStyle(context, selected);
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Material(
        color: selected ? colors.select : Colors.transparent,
        borderRadius: UfRadius.control,
        child: InkWell(
          key: Key('folder-${e.id}'),
          borderRadius: UfRadius.control,
          hoverColor: colors.panelHover,
          onTap: () => setState(() {
            _selected = e.id;
            open ? _collapsed.add(e.id) : _collapsed.remove(e.id);
          }),
          child: Container(
            constraints: const BoxConstraints(minHeight: UfHeight.small),
            padding: EdgeInsets.only(left: 8.0 + depth * 14, right: 4),
            child: Row(
              spacing: 8,
              children: [
                Icon(
                  open ? UfIcons.caretDown : UfIcons.caretRight,
                  size: 12,
                  color: selected ? colors.accentText : colors.muted,
                ),
                Expanded(
                  child: Text(
                    e.name ?? '',
                    style: style,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selected && e.orgId != null)
                  ..._orgFolderButtons(context, e),
                if (selected)
                  _editButton(context, e)
                else
                  Text(
                    '$hosts',
                    style: Theme.of(context).textTheme.bodySmall!
                        .copyWith(color: colors.muted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 13.5 px; a selected row is `accentText` in 600.
  static TextStyle _rowStyle(BuildContext context, bool selected) {
    final colors = UfColors.of(context);
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: 13.5,
      height: 1.3,
      color: selected ? colors.accentText : colors.text,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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
    final padding = EdgeInsets.fromLTRB(26.0 + depth * 14, 6, 4, 6);
    final muted = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: colors.muted);
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
          style: muted.copyWith(fontSize: 13.5),
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
              borderRadius: UfRadius.control,
              child: InkWell(
                key: Key('host-${e.id}'),
                borderRadius: UfRadius.control,
                hoverColor: colors.panelHover,
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
                    spacing: 8,
                    children: [
                      Seal(state: state.sealFor(e.id)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.name ?? '',
                              overflow: TextOverflow.ellipsis,
                              style: _rowStyle(context, selected),
                            ),
                            if (target != null)
                              Text(
                                target,
                                overflow: TextOverflow.ellipsis,
                                style: monoStyle.copyWith(
                                  fontSize: 11,
                                  color: colors.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (notes.isNotEmpty)
                        Flexible(child: UfTag(notes.join(', '))),
                      if (state.tabs.any((tab) => tab.hostId == e.id))
                        Icon(
                          UfIcons.terminalWindow,
                          size: 14,
                          color: colors.muted,
                          semanticLabel: l.tabOpen,
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
