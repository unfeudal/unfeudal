// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../config/features.dart';
import '../../db/db.dart';
import '../../orgs/org_access.dart';
import '../../orgs/rotations.dart';
import '../app.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';
import '../validate.dart';

/// The org of a live (not purged) org folder, else 404; shared by the folder routes.
Future<String> liveOrgFolder(Tx tx, String folderId) async {
  final rows = await tx.query(
    "SELECT org_id FROM items WHERE id = @f AND type = 'folder' AND org_id IS NOT NULL AND purged = 0",
    {'f': folderId},
  );
  if (rows.isEmpty) throw ApiError(ApiErrorCode.notFound, 'Not found.');
  return rows.single['org_id']! as String;
}

Never _bad(String rule) =>
    throw ApiError(ApiErrorCode.invalidRequest, 'entries: $rule');

Set<Permission> _permissionList(Object? v) {
  if (v is! List) _bad('allow and deny must be lists');
  return {
    for (final name in v)
      Permission.values.where((p) => p.name == name).firstOrNull ??
          _bad('unknown permission'),
  };
}

/// 4. shape, known permissions, teams never deny, one entry per principal · 5. users: user_overrides on,
/// enabled members · 6. teams: teams on, teams of the org.
List<AclEntry> _parseEntries(
  List<Map<String, Object?>> raw,
  String folder,
  OrgSnapshot org,
  Features features,
) {
  final seen = <(PrincipalType, String)>{};
  final out = <AclEntry>[];
  for (final e in raw) {
    final type =
        PrincipalType.values
            .where((t) => t.name == e['principalType'])
            .firstOrNull ??
        _bad('principalType must be user or team');
    final id = e['principalId'];
    if (id is! String || !isUuid(id)) _bad('principalId must be a UUID');
    final allow = _permissionList(e['allow']);
    final deny = _permissionList(e['deny']);
    if (type == PrincipalType.team && deny.isNotEmpty) {
      _bad('a team entry cannot deny');
    }
    if (!seen.add((type, id))) _bad('one entry per principal');
    if (type == PrincipalType.user) {
      if (!features.enabled(Flag.userOverrides)) {
        _bad('user entries are off on this server');
      }
      final member = org.members[id];
      if (member == null || member.disabled) {
        _bad('a user entry must name an enabled member');
      }
    } else {
      if (!features.enabled(Flag.teams)) {
        _bad('team entries are off on this server');
      }
      if (!org.teams.containsKey(id)) {
        _bad('a team entry must name a team of the organization');
      }
    }
    out.add(AclEntry(folder, type, id, allow, deny));
  }
  return out;
}

Future<Response> putAcl(Request request, String folder) async {
  final deps = depsOf(request), auth = authOf(request);
  parseUuid(folder);
  final raw = (await readJson(request))['entries'];
  if (raw is! List ||
      raw.length > 200 ||
      raw.any((e) => e is! Map<String, Object?>)) {
    throw ApiError(
      ApiErrorCode.invalidRequest,
      'entries must be a list of at most 200 objects.',
    ); // 1.
  }
  await deps.db.transaction((tx) async {
    final orgId = await liveOrgFolder(tx, folder); // 2. 404
    await requireMember(tx, orgId, auth.userId); // 3. 404
    final before = (await loadOrg(tx, orgId))!;
    final admin = before.members[auth.userId]!.isAdmin;
    if (!admin &&
        !permissionsOf(
          before,
          auth.userId,
          folder,
        ).contains(Permission.manage)) {
      throw ApiError(
        ApiErrorCode.forbidden,
        'You need manage on this folder.',
      ); // 3.
    }
    final entries = _parseEntries(
      raw.cast<Map<String, Object?>>(),
      folder,
      before,
      deps.features,
    ); // 4–6.
    await tx.execute('DELETE FROM acl_entries WHERE folder_id = @f', {
      'f': folder,
    });
    for (final e in entries) {
      await tx.execute(
        'INSERT INTO acl_entries (org_id, folder_id, principal_type, principal_id, allow, deny) '
        'VALUES (@o, @f, @t, @p, @a, @d)',
        {
          'o': orgId,
          'f': folder,
          't': e.principalType.name,
          'p': e.principalId,
          'a': jsonEncode([for (final p in e.allow) p.name]),
          'd': jsonEncode([for (final p in e.deny) p.name]),
        },
      );
    }
    final after = (await loadOrg(tx, orgId))!;
    if (!admin) {
      checkNoEscalation(before, after, auth.userId); // 7. 403
      if (!permissionsOf(
        after,
        auth.userId,
        folder,
      ).contains(Permission.manage)) {
        throw ApiError(
          ApiErrorCode.invalidRequest,
          'You cannot remove your own manage.',
        ); // 7. 400
      }
    }
    await recordRotations(tx, orgId, before, after, 'acl_change');
    await bumpOrgSeq(tx);
    // Audit hook: acl.changed [folderId]
  });
  return noContent();
}
