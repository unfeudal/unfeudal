// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../audit/audit_log.dart';
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
    await auditWriter(request, tx)(AuditScope.org(orgId), 'acl.changed', [
      folder,
    ]);
  });
  return noContent();
}

Future<Response> putFolderKeys(Request request, String folder) async {
  final deps = depsOf(request), auth = authOf(request);
  parseUuid(folder);
  final body = await readJson(request);
  final version = body['version'];
  final rawWraps = body['wrapped'];
  if (version is! int || rawWraps is! List || rawWraps.length > 1000) {
    throw ApiError(
      ApiErrorCode.invalidRequest,
      'version and wrapped are required.',
    ); // 1.
  }
  final List<WrappedFolderKeys> wraps;
  final FolderKeyHistory? history;
  try {
    wraps = [for (final w in rawWraps) WrappedFolderKeys.fromJson(w)];
    history = body['history'] == null
        ? null
        : FolderKeyHistory.fromJson(body['history']);
  } on FormatException catch (e) {
    throw ApiError(ApiErrorCode.invalidRequest, 'invalid wrap: ${e.message}');
  }
  final users = wraps.map((w) => w.userId).toSet();
  if (wraps.any((w) => w.userId == null) || users.length != wraps.length) {
    throw ApiError(
      ApiErrorCode.invalidRequest,
      'one wrap per user, userId required.',
    );
  }
  await deps.db.transaction((tx) async {
    final orgId = await liveOrgFolder(tx, folder); // 2.
    final caller = await requireMember(tx, orgId, auth.userId);
    final org = (await loadOrg(tx, orgId))!;
    final current = await currentKeyVersion(tx, folder);
    final item = (await tx.query(
      'SELECT revision, body FROM items WHERE id = @f',
      {'f': folder},
    )).single;
    final firstUpload =
        current == 0 &&
        item['revision'] == 1 &&
        (jsonDecode(item['body']! as String) as Map)['updatedBy'] ==
            auth.userId &&
        permissionsOf(org, auth.userId, folder).contains(Permission.edit);
    if (!caller.isAdmin && !firstUpload) {
      throw ApiError(ApiErrorCode.forbidden, 'Admins hand off folder keys.');
    }
    final rotation = current >= 1 && version == current + 1;
    if (version != max(current, 1) && !rotation) {
      throw ApiError(
        ApiErrorCode.invalidRequest,
        'version must be ${max(current, 1)} or ${current + 1}.',
      ); // 3.
    }
    String label(PayloadPart p) =>
        KeyIds.sealed(KeyIds.folder(folder, version, p));
    for (final w in wraps) {
      // 4.
      final perms = permissionsOf(org, w.userId!, folder);
      if (w.version != version ||
          !perms.contains(Permission.view) ||
          (w.secret != null && !perms.contains(Permission.connect)) ||
          w.meta.keyId != label(PayloadPart.meta) ||
          (w.secret != null && w.secret!.keyId != label(PayloadPart.secret))) {
        throw ApiError(
          ApiErrorCode.invalidRequest,
          'invalid wrap for ${w.userId}.',
        );
      }
    }
    if (rotation) {
      // 5.
      final readers = org.members.keys.where(
        (u) => permissionsOf(org, u, folder).contains(Permission.view),
      );
      if (history == null ||
          history.version != version ||
          !users.containsAll(readers)) {
        throw ApiError(
          ApiErrorCode.invalidRequest,
          'a rotation needs its history and a wrap for every reader.',
        );
      }
      await tx.execute('DELETE FROM folder_keys WHERE folder_id = @f', {
        'f': folder,
      });
      await tx.execute('DELETE FROM folder_key_history WHERE folder_id = @f', {
        'f': folder,
      });
      await tx.execute(
        'INSERT INTO folder_key_history (org_id, folder_id, version, body) VALUES (@o, @f, @v, @b)',
        {
          'o': orgId,
          'f': folder,
          'v': version,
          'b': jsonEncode(
            history!.toJson(),
          ), // checked above; the awaits stop promotion,
        },
      );
      await tx.execute(
        'UPDATE pending_rotations SET rotated_version = @v WHERE folder_id = @f',
        {'v': version, 'f': folder},
      );
    }
    for (final w in wraps) {
      await tx.execute(
        'INSERT INTO folder_keys (org_id, folder_id, user_id, version, meta_wrapped, secret_wrapped) VALUES (@o, @f, @u, @v, @m, @s) '
        'ON CONFLICT (folder_id, user_id) DO UPDATE SET version = @v, meta_wrapped = @m, secret_wrapped = @s',
        {
          'o': orgId,
          'f': folder,
          'u': w.userId,
          'v': version,
          'm': jsonEncode(w.meta.toJson()),
          's': w.secret == null ? null : jsonEncode(w.secret!.toJson()),
        },
      );
    }
    await bumpOrgSeq(tx);
    await auditWriter(request, tx)(
      AuditScope.org(orgId),
      rotation ? 'folder.keys_rotated' : 'folder.keys_shared',
      [folder],
    );
  });
  return noContent();
}

Future<Response> rotationDone(Request request, String folder) async {
  final deps = depsOf(request), auth = authOf(request);
  parseUuid(folder);
  await deps.db.transaction((tx) async {
    final orgId = await liveOrgFolder(tx, folder); // 1.
    await requireMember(tx, orgId, auth.userId, admin: true); // 2.
    final pending = (await tx.query(
      'SELECT rotated_version FROM pending_rotations WHERE folder_id = @f',
      {'f': folder},
    )).firstOrNull;
    if (pending == null) return; // 3. idempotent
    final current = await currentKeyVersion(tx, folder);
    final stale = ApiError(
      ApiErrorCode.conflict,
      'Some items still use the previous keys.',
    );
    if (pending['rotated_version'] != current) throw stale; // 4.
    // 5. the folder itself and its non-folder items (subfolders are sealed with their own keys), trash included
    for (final r in await tx.query(
      "SELECT body FROM items WHERE purged = 0 AND (id = @f OR (folder_id = @f AND type <> 'folder'))",
      {'f': folder},
    )) {
      final item = jsonDecode(r['body']! as String) as Map<String, Object?>;
      final secret = item['secret'] as Map<String, Object?>?;
      if ((item['meta'] as Map?)?['keyId'] !=
              KeyIds.folder(folder, current, PayloadPart.meta) ||
          (secret != null &&
              secret['keyId'] !=
                  KeyIds.folder(folder, current, PayloadPart.secret))) {
        throw stale;
      }
    }
    await tx.execute('DELETE FROM pending_rotations WHERE folder_id = @f', {
      'f': folder,
    });
    await bumpOrgSeq(tx);
    await auditWriter(request, tx)(
      AuditScope.org(orgId),
      'folder.rotation_done',
      [folder],
    );
  });
  return noContent();
}
