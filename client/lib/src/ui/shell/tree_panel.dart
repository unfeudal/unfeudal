// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/icons.dart';
import '../../design/seal.dart';
import '../../design/tokens.dart';
import '../../vault/vault.dart';
import 'shortcuts.dart';

/// The personal vault as a tree of folders and hosts, with a search over name, address and tags.
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
  final void Function(VaultEntry entry)? onEdit;

  @override
  State<TreePanel> createState() => _TreePanelState();
}

class _TreePanelState extends State<TreePanel> {
  final _query = TextEditingController();
  final _collapsed = <String>{};
  ({String id, DateTime at})? _lastTap;

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
    final visible = [
      for (final e in vault?.entries ?? const <VaultEntry>[])
        if (!vault!.isTrashed(e.id) && _shown(e)) e,
    ];
    final query = _query.text.trim().toLowerCase();
    final rows = query.isEmpty
        ? _tree(context, state, visible)
        : [
            for (final e in visible)
              if (e.kind == ItemKind.host && _matches(e, query))
                _row(context, state, e, depth: 0),
          ];
    return Container(
      color: colors.side,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text(
            l.vaultPersonal,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          TextField(
            key: const Key('tree-search'),
            controller: _query,
            focusNode: widget.searchFocus,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l.treeSearch(UfShortcuts.label(UfShortcut.focusSearch)),
              prefixIcon: const Icon(UfIcons.magnifyingGlass, size: 18),
              isDense: true,
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      l.treeEmpty,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.muted),
                    ),
                  )
                : ListView(children: rows),
          ),
          TextButton.icon(
            key: const Key('tree-new-host'),
            onPressed: readOnly ? null : widget.onNewHost,
            icon: const Icon(UfIcons.plus, size: 18),
            label: Text(l.treeNewHost),
          ),
          TextButton.icon(
            key: const Key('tree-new-folder'),
            onPressed: readOnly ? null : widget.onNewFolder,
            icon: const Icon(UfIcons.folderSimplePlus, size: 18),
            label: Text(l.treeNewFolder),
          ),
        ],
      ),
    );
  }

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
        out.add(_folderRow(context, e, depth, open));
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
    iconSize: 16,
    onPressed: widget.onEdit == null ? null : () => widget.onEdit!(e),
    icon: const Icon(UfIcons.pencil),
  );

  Widget _folderRow(BuildContext context, VaultEntry e, int depth, bool open) {
    final colors = UfColors.of(context);
    return InkWell(
      key: Key('folder-${e.id}'),
      borderRadius: BorderRadius.circular(8),
      onTap: () =>
          setState(() => open ? _collapsed.add(e.id) : _collapsed.remove(e.id)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(8.0 + depth * 14, 6, 8, 6),
        child: Row(
          spacing: 6,
          children: [
            Icon(
              open ? UfIcons.caretDown : UfIcons.caretRight,
              size: 12,
              color: colors.muted,
            ),
            Expanded(
              child: Text(
                e.name ?? '',
                style: Theme.of(context).textTheme.labelSmall!
                    .copyWith(color: colors.muted),
              ),
            ),
            _editButton(context, e),
          ],
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
    final padding = EdgeInsets.fromLTRB(22.0 + depth * 14, 7, 8, 7);
    final muted = TextStyle(color: colors.muted);
    if (e.state == EntryState.unreadable || e.state == EntryState.unsupported) {
      return Padding(
        key: Key('host-${e.id}'),
        padding: padding,
        child: Text(
          e.state == EntryState.unreadable
              ? l.treeUnreadable
              : l.treeUnsupported,
          style: muted,
        ),
      );
    }
    void connect() => state.connect(e.id);
    final notes = [
      if (e.state == EntryState.readOnly) l.treeReadOnly,
      if (e.pending) l.treePending,
    ];
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): connect},
      child: Focus(
        child: Builder(
          builder: (row) => InkWell(
            key: Key('host-${e.id}'),
            borderRadius: BorderRadius.circular(8),
            // a click selects the row (its own focus node, so Enter connects); a second one in time connects.
            // Detected here: onDoubleTap would hold back onTap and leave a timer behind every click
            onTap: () {
              Focus.of(row).requestFocus();
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
                    child: Text(e.name ?? '', overflow: TextOverflow.ellipsis),
                  ),
                  if (notes.isNotEmpty)
                    Flexible(
                      child: Text(
                        notes.join(', '),
                        style: muted,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  _editButton(context, e),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
