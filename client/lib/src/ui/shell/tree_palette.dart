// SPDX-License-Identifier: Apache-2.0
part of 'tree_panel.dart';

// The palette over the tree, following the search field it opened from; a tap outside closes it.
class _PaletteOverlay extends StatelessWidget {
  const _PaletteOverlay({
    required this.link,
    required this.focusNode,
    required this.groups,
    required this.onQueryChanged,
    required this.onDismiss,
  });

  final LayerLink link;
  final FocusNode focusNode;
  final List<UfPaletteGroup> groups;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Positioned(
    width: math.min(560, MediaQuery.sizeOf(context).width - 32),
    child: CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      child: TapRegion(
        onTapOutside: (_) => onDismiss(),
        child: Material(
          type: MaterialType.transparency,
          child: UfCommandPalette(
            focusNode: focusNode,
            hint: AppLocalizations.of(context).treeSearchHint,
            groups: groups,
            onQueryChanged: onQueryChanged,
            onDismiss: onDismiss,
          ),
        ),
      ),
    ),
  );
}

extension _PaletteGroups on _TreePanelState {
  // Hosts of this vault matching the query, then snippets of this vault and the personal one (inserted into
  // the active session), then the actions the panel allows.
  List<UfPaletteGroup> _paletteGroups(
    BuildContext context,
    AppState state, {
    required VoidCallback? newHost,
    required VoidCallback? newFolder,
  }) {
    if (state.vault == null) return const [];
    final l = AppLocalizations.of(context);
    final query = _paletteQuery.trim().toLowerCase();
    final actions = [
      if (newHost != null) (l.treeNewHost, UfIcons.plus, newHost),
      if (newFolder != null)
        (l.treeNewFolder, UfIcons.folderSimplePlus, newFolder),
      if (widget.onSettings case final settings?)
        (l.railSettings, UfIcons.gear, settings),
      (l.railLock, UfIcons.lock, state.lock),
    ];
    return [
      _hostGroup(l, state, query),
      _snippetGroup(l, state, query),
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

  // A palette shows the best few of each group; typing narrows the rest.
  static const _paletteLimit = 20;

  UfPaletteGroup _hostGroup(AppLocalizations l, AppState state, String query) {
    final vault = state.vault!;
    final orgId = state.orgs?.selected;
    final hosts = [
      for (final e in vault.ofKind(ItemKind.host))
        if (e.orgId == orgId &&
            !vault.isTrashed(e.id) &&
            e.state != EntryState.unreadable &&
            e.state != EntryState.unsupported &&
            _matches(e, query))
          e,
    ]..sort(byName);
    return UfPaletteGroup(l.paletteHosts(vaultNameOf(l, state, orgId)), [
      for (final e in hosts.take(_paletteLimit))
        UfPaletteRow(
          label: e.name ?? '',
          detail: [
            ?vault.entry(e.folderId ?? '')?.name,
            ?_target(state, e.id),
          ].join(l.listSeparator),
          hint: l.paletteConnect,
          icon: Seal(state: state.connections.sealFor(e.id)),
          onSelected: _thenClose(() => state.connections.connect(e.id)),
        ),
    ]);
  }

  UfPaletteGroup _snippetGroup(
    AppLocalizations l,
    AppState state,
    String query,
  ) {
    final vault = state.vault!;
    final orgId = state.orgs?.selected;
    final tab = state.connections.activeSession;
    final canInsert = tab?.state == SealState.connected;
    final snippets = [
      for (final s in SnippetStore(vault).list(query: query))
        if (vault.entry(s.id)?.orgId case final owner
            when owner == null || owner == orgId)
          (snippet: s, owner: owner),
    ];
    return UfPaletteGroup(l.searchSnippets, [
      for (final (:snippet, :owner) in snippets.take(_paletteLimit))
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
                    confirm: () => confirmUnsafeMultiline(context),
                  )
                : null,
          ),
        ),
    ]);
  }
}
