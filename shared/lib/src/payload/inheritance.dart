// SPDX-License-Identifier: Apache-2.0
import 'folder.dart';
import 'host.dart';

class ResolvedHost {
  const ResolvedHost({
    required this.port,
    this.user,
    this.identityId,
    this.jumpHostId,
    required this.sources,
  });

  final int port;
  final String? user;
  final String? identityId;
  final String? jumpHostId;

  /// Field name to where its value comes from: 'host', a folder id or 'default'.
  final Map<String, String> sources;
}

/// The host's own value, else the nearest folder default along the parent
/// chain, else port 22 and nulls. The walk stops at a missing or unreadable
/// folder and on a cycle.
ResolvedHost resolveHost(
  HostMeta host,
  String? folderId,
  FolderMeta? Function(String id) folderOf, {
  String? hostId,
  required String? Function(String id) parentOf,
}) {
  final chain = <(String, FolderMeta)>[];
  final seen = <String>{};
  for (var id = folderId; id != null && seen.add(id);) {
    final meta = folderOf(id); // null = missing or unreadable: stop
    if (meta == null) break;
    chain.add((id, meta));
    id = parentOf(id);
  }
  final sources = <String, String>{};
  T? pick<T>(String field, T? own, T? Function(FolderDefaults d) of) {
    if (own != null) {
      sources[field] = 'host';
      return own;
    }
    for (final (id, meta) in chain) {
      final v = of(meta.defaults);
      if (v != null) {
        sources[field] = id;
        return v;
      }
    }
    sources[field] = 'default';
    return null;
  }

  // perMember: the identity comes from the caller's hostBinding, never inherited.
  final perMember = host.identityMode == IdentityMode.perMember;
  final port = pick('port', host.port, (d) => d.port) ?? 22;
  final user = pick('user', host.user, (d) => d.user);
  final identityId = pick(
    'identityId',
    perMember ? null : host.identityId,
    (d) => perMember ? null : d.identityId,
  );
  var jumpHostId = pick('jumpHostId', host.jumpHostId, (d) => d.jumpHostId);
  if (jumpHostId != null && jumpHostId == hostId) {
    jumpHostId = null; // the host itself: direct connection
    sources['jumpHostId'] = 'default';
  }
  return ResolvedHost(
    port: port,
    user: user,
    identityId: identityId,
    jumpHostId: jumpHostId,
    sources: sources,
  );
}
