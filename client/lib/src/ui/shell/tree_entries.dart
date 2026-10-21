// SPDX-License-Identifier: Apache-2.0
part of 'tree_panel.dart';

List<VaultEntry> _visibleEntries(AppState state) {
  final vault = state.vault;
  final orgId = state.orgs?.selected;
  return [
    for (final e in vault?.entries ?? const <VaultEntry>[])
      if (e.orgId == orgId && !vault!.isTrashed(e.id) && _shown(e)) e,
  ];
}

// An org vault: both buttons need edit somewhere in the cached block.
bool _canEditIn(OrgController? orgs, OrgSummary? org) =>
    org == null ||
    orgs!.isAdmin(org.id) ||
    (orgs.block?.folderTree ?? const <FolderNode>[]).any(
      (n) =>
          n.orgId == org.id &&
          orgs.permissions(org.id, n.folderId).contains(Permission.edit),
    );

// The vault opening, or a first sync still bringing its items; a paused or failed round shows the vault.
bool _isLoading(AppState state, List<VaultEntry> visible) =>
    state.vault == null ||
    (visible.isEmpty && (state.sync?.isFirstSyncPending ?? false));

// `user@address:port` of a host, from its resolved values.
String? _target(AppState state, String hostId) =>
    switch (state.vault?.hostLookup(hostId)) {
      (:final meta, :final resolved, isOrg: _) => [
        if (resolved.user case final user?) '$user@',
        meta.address,
        if (resolved.port != 22) ':${resolved.port}',
      ].join(),
      null => null,
    };

// Hosts, folders, and the entries the tree must label (unreadable, newer type).
bool _shown(VaultEntry e) =>
    e.kind == ItemKind.host ||
    e.kind == ItemKind.folder ||
    e.state == EntryState.unsupported;

bool _matches(VaultEntry e, String query) {
  final meta = e.meta ?? const {};
  final texts = [
    meta['name'],
    meta['address'],
    ...switch (meta['tags']) {
      final List<Object?> tags => tags,
      _ => const <Object?>[],
    },
  ];
  return texts.whereType<String>().any((t) => t.toLowerCase().contains(query));
}
