// SPDX-License-Identifier: Apache-2.0
part of 'vault.dart';

extension EditorChoices on Vault {
  /// The `ok` entries of [kind] in [orgId]'s vault, the personal vault when null.
  List<VaultEntry> usableOfKind(ItemKind kind, {required String? orgId}) => [
    for (final e in ofKind(kind))
      if (e.state == EntryState.ok && e.orgId == orgId) e,
  ];

  /// Whether [candidate] as the jump host of [hostId], or as the default of folder [folderId] when [hostId] is
  /// null, leaves every affected chain free of loops, missing hops and excess depth.
  bool jumpKeepsChainsValid({
    String? hostId,
    String? folderId,
    required String candidate,
  }) {
    try {
      if (hostId case final host?) {
        resolveJumpChain(
          host,
          (id) => id == host ? _withJump(host, candidate) : _untrashedHost(id),
        );
        return true;
      }
      // A new folder: no host inherits from it yet.
      if (folderId == null) return true;
      final draft = _draftFolder(folderId, candidate);
      ResolvedHost? lookup(String id) {
        final e = _entries[id];
        if (e == null || isTrashed(id) || hostLookup(id) == null) return null;
        return resolveHost(
          HostMeta.fromJson(e.meta),
          e.folderId,
          (f) => f == folderId ? draft : _folderOf(f),
          hostId: id,
          parentOf: (f) => _entries[f]?.folderId,
        );
      }

      for (final e in ofKind(ItemKind.host)) {
        if (lookup(e.id)?.sources['jumpHostId'] == folderId) {
          resolveJumpChain(e.id, lookup);
        }
      }
      return true;
    } on Exception {
      // JumpLoop, JumpTooDeep or JumpHostMissing.
      return false;
    }
  }

  ResolvedHost? _untrashedHost(String id) =>
      isTrashed(id) ? null : hostLookup(id)?.resolved;

  ResolvedHost? _withJump(String id, String jump) {
    final r = _untrashedHost(id);
    return r == null
        ? null
        : ResolvedHost(
            port: r.port,
            user: r.user,
            identityId: r.identityId,
            jumpHostId: jump,
            sources: {...r.sources, 'jumpHostId': 'host'},
          );
  }

  FolderMeta? _draftFolder(String id, String jump) {
    final e = _entries[id];
    if (e == null || e.state != EntryState.ok) return null;
    final defaults = switch (e.meta?['defaults']) {
      final Map<String, Object?> d => d,
      _ => const <String, Object?>{},
    };
    return FolderMeta.fromJson({
      ...?e.meta,
      'defaults': {...defaults, 'jumpHostId': jump},
    });
  }
}
