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
import '../../design/inputs.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/palette.dart';
import '../../design/rows.dart';
import '../../design/seal.dart';
import '../../design/tokens.dart';
import '../../terminal/snippet_insertion.dart';
import '../../vault/snippet_store.dart';
import '../../vault/vault.dart';
import '../hosts/editor_frame.dart' show vaultNameOf;
import '../terminal/multiline_dialog.dart';
import '../orgs/members_screen.dart' show confirmAndLeaveOrg;
import '../orgs/why_rights_view.dart';
import 'shortcuts.dart';

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
    final colors = UfColors.of(context);
    final vault = state.vault;
    final readOnly = state.sync?.readOnly ?? true;
    final orgs = state.orgs;
    final orgId = orgs?.selected;
    final org = orgs?.byId(orgId);
    final awaiting = org != null && !org.isConfirmed;
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
    final rows = _tree(context, state, visible);
    final sync = state.sync;
    // the vault opening, or a first sync still bringing its items; a paused or failed round shows the vault
    final loading =
        vault == null ||
        (visible.isEmpty &&
            sync != null &&
            sync.online &&
            sync.lastSyncAt == null &&
            sync.lastError == null &&
            !sync.restorePending &&
            (sync.compat == null || sync.compat!.api != null));
    final text = Theme.of(context).textTheme;
    final newFolderBlocked = org != null && !online;
    final canNewHost = !readOnly && orgEdit && !awaiting;
    final canNewFolder = canNewHost && !newFolderBlocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        OverlayPortal(
          controller: _palette,
          overlayChildBuilder: (context) => Positioned(
            width: math.min(560, MediaQuery.sizeOf(context).width - 32),
            child: CompositedTransformFollower(
              link: _paletteAnchor,
              showWhenUnlinked: false,
              child: TapRegion(
                onTapOutside: (_) => _closePalette(),
                child: Material(
                  type: MaterialType.transparency,
                  child: UfCommandPalette(
                    focusNode: _paletteFocus,
                    hint: l.treeSearchHint,
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
                ),
              ),
            ),
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
                onPressed: canNewHost ? widget.onNewHost : null,
                icon: const Icon(UfIcons.plus),
              ),
              IconButton(
                key: const Key('tree-new-folder'),
                tooltip: newFolderBlocked
                    ? l.treeNewFolderOnline
                    : l.treeNewFolder,
                onPressed: canNewFolder ? widget.onNewFolder : null,
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
              : loading
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: UfTreeSkeleton(),
                )
              : rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    l.treeEmpty,
                    style: text.bodySmall!.copyWith(color: colors.muted),
                  ),
                )
              : UfStagger(
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, i) =>
                        UfStaggerItem(index: i, child: rows[i]),
                  ),
                ),
        ),
      ],
    );
  }

  // Hosts of this vault matching the query, then snippets of this vault and the personal one (inserted into
  // the active session), then the actions the panel allows.
  List<UfPaletteGroup> _paletteGroups(
    BuildContext context,
    AppState state, {
    required VoidCallback? newHost,
    required VoidCallback? newFolder,
  }) {
    final vault = state.vault;
    if (vault == null) return const [];
    final l = AppLocalizations.of(context);
    final query = _paletteQuery.trim().toLowerCase();
    final orgId = state.orgs?.selected;
    // ponytail: the first 20 of each group, typing narrows them; a lazy list if vaults outgrow that
    const shown = 20;
    final hosts = [
      for (final e in vault.ofKind(ItemKind.host))
        if (e.orgId == orgId &&
            !vault.isTrashed(e.id) &&
            e.state != EntryState.unreadable &&
            e.state != EntryState.unsupported &&
            _matches(e, query))
          e,
    ]..sort(byName);
    final tab = state.activeSession;
    final canInsert = tab?.state == SealState.connected;
    final snippets = [
      for (final s in SnippetStore(vault).list(query: query))
        if (vault.entry(s.id)?.orgId case final owner
            when owner == null || owner == orgId)
          (snippet: s, owner: owner),
    ];
    final actions = [
      if (newHost != null) (l.treeNewHost, UfIcons.plus, newHost),
      if (newFolder != null)
        (l.treeNewFolder, UfIcons.folderSimplePlus, newFolder),
      if (widget.onSettings case final settings?)
        (l.railSettings, UfIcons.gear, settings),
      (l.railLock, UfIcons.lock, state.lock),
    ];
    return [
      UfPaletteGroup(l.paletteHosts(vaultNameOf(l, state, orgId)), [
        for (final e in hosts.take(shown))
          UfPaletteRow(
            label: e.name ?? '',
            detail: [
              ?vault.entry(e.folderId ?? '')?.name,
              ?_target(state, e.id),
            ].join(' · '),
            hint: l.paletteConnect,
            icon: Seal(state: state.sealFor(e.id)),
            onSelected: _thenClose(() => state.connect(e.id)),
          ),
      ]),
      UfPaletteGroup(l.searchSnippets, [
        for (final (:snippet, :owner) in snippets.take(shown))
          UfPaletteRow(
            label: snippet.meta.name,
            detail: canInsert
                ? vaultNameOf(l, state, owner)
                : l.snippetNoTerminal,
            hint: canInsert ? l.paletteInsert : null,
            icon: const Icon(UfIcons.terminal),
            onSelected: _thenClose(
              canInsert
                  ? () => insertSnippet(
                      tab!,
                      snippet.meta.command,
                      confirm: () => confirmUnsafeMultiline(this.context),
                    )
                  : null,
            ),
          ),
      ]),
      UfPaletteGroup(l.paletteActions, [
        for (final (label, icon, run) in actions)
          if (label.toLowerCase().contains(query))
            UfPaletteRow(
              label: label,
              icon: Icon(icon),
              onSelected: _thenClose(run),
            ),
      ]),
    ];
  }

  // `user@address:port` of a host, from its resolved values.
  static String? _target(AppState state, String hostId) =>
      switch (state.vault?.hostLookup(hostId)) {
        (:final meta, :final resolved, org: _) => [
          if (resolved.user case final user?) '$user@',
          meta.address,
          if (resolved.port != 22) ':${resolved.port}',
        ].join(),
        null => null,
      };

  // Hosts, folders, and the entries the tree must label (unreadable, newer type).
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
    final padding = EdgeInsets.fromLTRB(8.0 + depth * 14, 5, 4, 5);
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
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: UfHeight.small,
                    ),
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
      ),
    );
  }
}
