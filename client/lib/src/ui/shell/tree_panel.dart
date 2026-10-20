// SPDX-License-Identifier: Apache-2.0
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/buttons.dart';
import '../../design/feedback.dart';
import '../../design/icons.dart';
import '../../design/inputs.dart';
import '../../design/motion.dart';
import '../../design/palette.dart';
import '../../design/rows.dart';
import '../../design/seal.dart';
import '../../design/tokens.dart';
import '../../orgs/org_controller.dart';
import '../../terminal/snippet_insertion.dart';
import '../../vault/snippet_store.dart';
import '../../vault/vault.dart';
import '../hosts/editor_frame.dart' show vaultNameOf;
import '../orgs/members_screen.dart' show confirmAndLeaveOrg;
import '../orgs/why_rights_view.dart';
import '../terminal/multiline_dialog.dart';
import 'shortcuts.dart';

part 'tree_entries.dart';
part 'tree_palette.dart';
part 'tree_rows.dart';

/// The search and host tree of the selected vault (personal or an org). The search opens a command palette over
/// the tree: hosts by name, address or tag, snippets of this vault and the personal one, and actions.
class TreePanel extends StatefulWidget {
  const TreePanel({
    super.key,
    required this.searchFocus,
    this.onNewHost,
    this.onNewFolder,
    this.onEdit,
    this.onSettings,
  });

  /// Focusing it (a click, Ctrl K) opens the palette.
  final FocusNode searchFocus;

  /// Null keeps the button disabled; both are disabled while the server is read-only.
  final VoidCallback? onNewHost;
  final VoidCallback? onNewFolder;

  /// Opens the editor of a host or folder (the pencil of its row).
  final void Function(VaultEntry entry)? onEdit;
  final VoidCallback? onSettings;

  @override
  State<TreePanel> createState() => _TreePanelState();
}

class _TreePanelState extends State<TreePanel> {
  final _palette = OverlayPortalController();
  final _paletteAnchor = LayerLink();
  final _paletteFocus = FocusNode();
  var _paletteQuery = '';
  final _collapsed = <String>{};
  ({String id, DateTime at})? _lastTap;

  // The row the last click selected: highlighted, with its address and pencil.
  String? _selected;

  @override
  void initState() {
    super.initState();
    widget.searchFocus.addListener(_onSearchFocus);
  }

  @override
  void dispose() {
    widget.searchFocus.removeListener(_onSearchFocus);
    _paletteFocus.dispose();
    super.dispose();
  }

  void _onSearchFocus() {
    if (!widget.searchFocus.hasFocus) return;
    if (_palette.isShowing) return _paletteFocus.requestFocus();
    setState(() => _paletteQuery = '');
    _palette.show();
    // the palette's field takes over from the one at rest, which still holds focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _paletteFocus.requestFocus();
    });
  }

  void _closePalette() {
    if (!_palette.isShowing) return;
    // left to the scope, focus would return to the field at rest and reopen the palette
    _paletteFocus.unfocus();
    _palette.hide();
  }

  // Closes the palette first, then runs the action.
  VoidCallback _thenClose(VoidCallback? action) => () {
    _closePalette();
    action?.call();
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final orgs = state.orgs;
    final org = orgs?.byId(orgs.selected);
    final awaiting = org != null && !org.isConfirmed;
    final visible = _visibleEntries(state);
    // an org vault's folders need the server
    final newFolderBlocked = org != null && !(state.sync?.online ?? false);
    final canNewHost =
        !(state.sync?.readOnly ?? true) && _canEditIn(orgs, org) && !awaiting;
    final canNewFolder = canNewHost && !newFolderBlocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        OverlayPortal(
          controller: _palette,
          overlayChildBuilder: (context) => _PaletteOverlay(
            link: _paletteAnchor,
            focusNode: _paletteFocus,
            groups: _paletteGroups(
              context,
              state,
              newHost: canNewHost ? widget.onNewHost : null,
              newFolder: canNewFolder ? widget.onNewFolder : null,
            ),
            onQueryChanged: (q) {
              setState(() => _paletteQuery = q);
              state.loquet.watch((q.length / 30).clamp(0, 1));
            },
            onDismiss: _closePalette,
          ),
          child: CompositedTransformTarget(
            link: _paletteAnchor,
            child: UfSearchField(
              key: const Key('tree-search'),
              focusNode: widget.searchFocus,
              hint: l.treeSearchHint,
              shortcut: UfShortcuts.searchLabel,
            ),
          ),
        ),
        _TreeHeader(
          onNewHost: canNewHost ? widget.onNewHost : null,
          onNewFolder: canNewFolder ? widget.onNewFolder : null,
          newFolderBlocked: newFolderBlocked,
        ),
        Expanded(
          child: _TreeBody(
            awaitingOrg: awaiting ? org : null,
            loading: _isLoading(state, visible),
            rows: _tree(context, state, visible),
          ),
        ),
      ],
    );
  }

  // Folders nested under their parent (a stored loop is cut by the seen-set); orphans at the root.
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
      final items = [...?children[parent]]..sort(byName);
      for (final e in items.where(
        (e) => e.kind == ItemKind.folder && folders.containsKey(e.id),
      )) {
        if (!seen.add(e.id)) continue;
        final open = !_collapsed.contains(e.id);
        final hosts = (children[e.id] ?? const <VaultEntry>[])
            .where((c) => c.kind == ItemKind.host)
            .length;
        out.add(_folderRow(context, e, depth: depth, open: open, hosts: hosts));
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
    onPressed: widget.onEdit == null ? null : () => widget.onEdit!(e),
    icon: const Icon(UfIcons.pencil),
  );

  // Access (with manage) and why, for an org folder.
  List<Widget> _orgFolderButtons(BuildContext context, VaultEntry e) {
    final l = AppLocalizations.of(context);
    final (:access, :why) = orgFolderAccessActions(context, e.orgId!, e.id);
    return [
      if (access != null)
        IconButton(
          key: Key('folder-access-${e.id}'),
          tooltip: l.aclTitle(e.name ?? ''),
          onPressed: access,
          icon: const Icon(UfIcons.users),
        ),
      IconButton(
        key: Key('folder-why-${e.id}'),
        tooltip: l.whyTitle,
        onPressed: why,
        icon: const Icon(UfIcons.info),
      ),
    ];
  }

  Widget _folderRow(
    BuildContext context,
    VaultEntry e, {
    required int depth,
    required bool open,
    required int hosts,
  }) {
    final colors = UfColors.of(context);
    final selected = _selected == e.id;
    final style = _rowStyle(context, selected);
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: UfFocusRing(
        child: Material(
          color: selected ? colors.select : Colors.transparent,
          borderRadius: UfRadius.control,
          child: InkWell(
            key: Key('folder-${e.id}'),
            borderRadius: UfRadius.control,
            hoverColor: colors.panelHover,
            hoverDuration: UfMotion.of(context).instant,
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
    final padding = EdgeInsets.fromLTRB(8.0 + depth * 14, 5, 4, 5);
    if (e.state == EntryState.unreadable || e.state == EntryState.unsupported) {
      return _unreadableRow(context, e, padding);
    }
    void connect() => state.connections.connect(e.id);
    final notes = [
      if (e.state == EntryState.readOnly) l.treeReadOnly,
      if (e.pending) l.treePending,
    ];
    final selected = _selected == e.id;
    final target = selected ? _target(state, e.id) : null;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): connect},
      child: Focus(
        child: Builder(
          builder: (row) => Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: UfFocusRing(
              child: Material(
                color: selected ? colors.select : Colors.transparent,
                borderRadius: UfRadius.control,
                child: InkWell(
                  key: Key('host-${e.id}'),
                  borderRadius: UfRadius.control,
                  hoverColor: colors.panelHover,
                  hoverDuration: UfMotion.of(context).instant,
                  onTap: () => _tapHost(row, e.id, connect),
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: UfHeight.small,
                    ),
                    padding: padding,
                    child: _HostLine(
                      seal: state.connections.sealFor(e.id),
                      name: e.name ?? '',
                      nameStyle: _rowStyle(context, selected),
                      target: target,
                      notes: notes,
                      hasOpenTab: state.connections.tabs.any(
                        (tab) => tab.hostId == e.id,
                      ),
                      editButton: selected ? _editButton(context, e) : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // A click selects the row (its own focus node, so Enter connects); a second one in time connects.
  // Detected here: onDoubleTap would hold back onTap and leave a timer behind every click.
  void _tapHost(BuildContext row, String hostId, VoidCallback connect) {
    Focus.of(row).requestFocus();
    setState(() => _selected = hostId);
    final now = DateTime.now();
    final last = _lastTap;
    if (last != null &&
        last.id == hostId &&
        now.difference(last.at) < kDoubleTapTimeout) {
      _lastTap = null;
      connect();
    } else {
      _lastTap = (id: hostId, at: now);
    }
  }
}
