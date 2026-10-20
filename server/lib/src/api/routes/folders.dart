// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../audit/audit_log.dart';
import '../../config/features.dart';
import '../../orgs/org_access.dart';
import '../../orgs/rotations.dart';
import '../app.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';
import '../validate.dart';

Set<Permission> _permissionList(Object? v) {
  if (v is! List) badField('entries', 'allow and deny must be lists');
  return {
    for (final name in v)
      Permission.values.asNameMap()[name] ??
          badField('entries', 'unknown permission'),
  };
}

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
        PrincipalType.values.asNameMap()[e['principalType']] ??
        badField('entries', 'principalType must be user or team');
    final id = e['principalId'];
    if (id is! String || !isUuid(id)) {
      badField('entries', 'principalId must be a UUID');
    }
    final allow = _permissionList(e['allow']);
    final deny = _permissionList(e['deny']);
    if (type == PrincipalType.team && deny.isNotEmpty) {
      badField('entries', 'a team entry cannot deny');
    }
    if (!seen.add((type, id))) badField('entries', 'one entry per principal');
    if (type == PrincipalType.user) {
      if (!features.enabled(Flag.userOverrides)) {
        badField('entries', 'user entries are off on this server');
      }
      final member = org.members[id];
      if (member == null || member.disabled) {
        badField('entries', 'a user entry must name an enabled member');
      }
    } else {
      if (!features.enabled(Flag.teams)) {
        badField('entries', 'team entries are off on this server');
      }
      if (!org.teams.containsKey(id)) {
        badField(
          'entries',
          'a team entry must name a team of the organization',
        );
      }
    }
    out.add(AclEntry(folder, type, id, allow, deny));
  }
  return out;
}

Future<Response> putAcl(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  final folder = parseUuid(request.params['folder']!);
  final raw = (await readJson(request))['entries'];
  if (raw is! List ||
      raw.length > 200 ||
      raw.any((e) => e is! Map<String, Object?>)) {
    throw ApiError(
      ApiErrorCode.invalidRequest,
      'entries must be a list of at most 200 objects.',
    );
  }
  await deps.db.transaction((tx) async {
    final orgId = await liveOrgFolder(tx, folder);
    await requireMember(tx, orgId, auth.userId);
    final before = (await loadOrg(tx, orgId))!;
    final admin = before.members[auth.userId]!.isAdmin;
    if (!admin &&
        !permissionsOf(
          before,
          auth.userId,
          folder,
        ).contains(Permission.manage)) {
      throw ApiError(ApiErrorCode.forbidden, 'You need manage on this folder.');
    }
    final entries = _parseEntries(
      raw.cast<Map<String, Object?>>(),
      folder,
      before,
      deps.features,
    );
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
    // A non-admin manager cannot grant more than they hold, nor lock
    // themselves out of the folder.
    if (!admin) {
      checkNoEscalation(before, after, auth.userId);
      if (!permissionsOf(
        after,
        auth.userId,
        folder,
      ).contains(Permission.manage)) {
        throw ApiError(
          ApiErrorCode.invalidRequest,
          'You cannot remove your own manage.',
        );
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

Future<Response> putFolderKeys(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  final folder = parseUuid(request.params['folder']!);
  final body = await readJson(request);
  final version = body['version'];
  final rawWraps = body['wrapped'];
  if (version is! int || rawWraps is! List || rawWraps.length > 1000) {
    throw ApiError(
      ApiErrorCode.invalidRequest,
      'version and wrapped are required.',
    );
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
    final orgId = await liveOrgFolder(tx, folder);
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
      );
    }
    String label(PayloadPart p) =>
        KeyIds.sealed(KeyIds.folder(folder, version, p));
    // Each user gets only the key parts their permissions on the folder allow.
    for (final w in wraps) {
      final access = FolderKeyAccess.of(permissionsOf(org, w.userId!, folder));
      if (w.version != version ||
          !access.hasMeta ||
          (w.secret != null && !access.hasSecret) ||
          w.meta.keyId != label(PayloadPart.meta) ||
          (w.secret != null && w.secret!.keyId != label(PayloadPart.secret))) {
        throw ApiError(
          ApiErrorCode.invalidRequest,
          'invalid wrap for ${w.userId}.',
        );
      }
    }
    // A rotation replaces every wrap, so no reader may be left without the new keys.
    if (rotation) {
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
      // history is checked non-null above; the awaits in between stop type promotion.
      await tx.execute(
        'INSERT INTO folder_key_history (org_id, folder_id, version, body) VALUES (@o, @f, @v, @b)',
        {
          'o': orgId,
          'f': folder,
          'v': version,
          'b': jsonEncode(history!.toJson()),
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

Future<Response> rotationDone(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  final folder = parseUuid(request.params['folder']!);
  await deps.db.transaction((tx) async {
    final orgId = await liveOrgFolder(tx, folder);
    await requireMember(tx, orgId, auth.userId, admin: true);
    final pending = (await tx.query(
      'SELECT rotated_version FROM pending_rotations WHERE folder_id = @f',
      {'f': folder},
    )).firstOrNull;
    // Idempotent: a repeated call after completion is a no-op.
    if (pending == null) return;
    final current = await currentKeyVersion(tx, folder);
    final stale = ApiError(
      ApiErrorCode.conflict,
      'Some items still use the previous keys.',
    );
    if (pending['rotated_version'] != current) throw stale;
    // The folder and its non-folder items, trash included; subfolders are
    // sealed with their own keys.
    for (final r in await tx.query(
      "SELECT body FROM items WHERE purged = 0 AND (id = @f OR (folder_id = @f AND type <> 'folder'))",
      {'f': folder},
    )) {
      final item = jsonDecode(r['body']! as String) as Map<String, Object?>;
      if (!sealedWithFolderKeys(
        (item['meta'] as Map?)?['keyId'],
        (item['secret'] as Map?)?['keyId'],
        folder,
        current,
      )) {
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
