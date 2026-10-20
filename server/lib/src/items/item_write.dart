// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:math';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/app.dart';
import '../api/errors.dart';
import '../api/middleware.dart';
import '../audit/audit_log.dart';
import '../audit/retention.dart';
import '../db/db.dart';
import '../orgs/org_access.dart';
import '../orgs/rotations.dart';

/// Parses the client body as an Item before the transaction, dropping server-set fields.
Item parseItemInput(String pathId, Map<String, Object?> body) {
  if (body.containsKey('id') && body['id'] != pathId) {
    throw ApiError.invalid('id must equal the path');
  }
  final json = {...body, 'id': pathId, 'secret': body['secret']}
    ..remove('purged')
    ..remove('revision')
    ..remove('createdAt')
    ..remove('updatedAt')
    ..remove('updatedBy')
    ..remove('updatedDevice');
  final Item item;
  try {
    // Checks type (1 to 64), schemaVersion (at least 1), deleted, the envelopes, folderId,
    // scope, and an orgId present exactly for org items.
    item = Item.fromJson(json);
  } on FormatException catch (e) {
    throw ApiError.invalid('invalid item: ${e.message}');
  }
  if (personalOnlyTypes.contains(item.type) &&
      (item.scope != ItemScope.personal || item.folderId != null)) {
    throw ApiError.invalid(
      '${item.type} items are personal and have no folder',
    );
  }
  return item;
}

/// Checks access, revision and quota, then writes, inside the caller's transaction.
Future<Item> writeItem(
  AppDeps deps,
  Tx tx,
  AuthContext auth,
  Item input,
  int ifMatch, {
  String? ip,
}) async {
  // first statement: one seq space, commit order = seq order
  final seq = await nextItemSeq(tx);
  final rows = await tx.query(
    'SELECT owner_user_id, org_id, folder_id, type, revision, deleted, purged, size, created_at, body FROM items WHERE id = @id',
    {'id': input.id},
  );
  final cur = rows.firstOrNull;
  final curBody = cur == null
      ? null
      : jsonDecode(cur['body'] as String) as Map<String, Object?>;
  ApiError conflict() => ApiError(
    ApiErrorCode.conflict,
    'The item changed on another device.',
    extra: {'item': curBody},
  );
  // Ownership comes first so a tombstone or a type of another account or org never shows.
  if (input.scope == ItemScope.personal) {
    // Another account's item, or an org item.
    if (cur != null && cur['owner_user_id'] != auth.userId) {
      throw ApiError(ApiErrorCode.forbidden, 'Not your item.');
    }
  } else {
    if (!deps.features.enabled(Flag.orgs)) {
      throw ApiError.orgsOff();
    }
    if (cur != null && cur['org_id'] != input.orgId) {
      throw ApiError(ApiErrorCode.forbidden, 'Not this organization\'s item.');
    }
    final member = await tx.query(
      "SELECT 1 AS x FROM org_members WHERE org_id = @o AND user_id = @u AND status = 'confirmed'",
      {'o': input.orgId, 'u': auth.userId},
    );
    if (member.isEmpty) throw ApiError.notFound();
  }
  // A purged item is a tombstone: no write revives it, whatever If-Match says.
  if (cur != null && cur['purged'] == 1) {
    throw conflict();
  }
  if (cur != null && cur['type'] != input.type) {
    throw ApiError.invalid('type is fixed at creation');
  }
  final wasDeleted = cur?['deleted'] == 1;
  final storedSecret = curBody?['secret'];
  final folderChanged = cur != null && cur['folder_id'] != input.folderId;
  // Personal items always use the `user` keyId, so only org items change key.
  final keyChanged =
      cur != null && (curBody?['meta'] as Map?)?['keyId'] != input.meta?.keyId;
  // The kept secret is sealed with the old key, so it cannot follow a move or re-seal.
  if (storedSecret != null &&
      input.secret == null &&
      (folderChanged || keyChanged)) {
    throw ApiError.invalid('a move or a re-seal re-seals the secret');
  }
  if (input.scope == ItemScope.personal) {
    await _checkPersonalFolder(tx, auth, input);
  } else {
    await checkOrgWrite(tx, auth, input, cur);
  }
  if (cur != null &&
      await isTrashed(
        tx,
        deleted: wasDeleted,
        folderId: cur['folder_id'] as String?,
      )) {
    final restore =
        (wasDeleted && !input.deleted) ||
        (folderChanged &&
            !await isTrashed(
              tx,
              deleted: input.deleted,
              folderId: input.folderId,
            ));
    final reseal = !folderChanged && input.deleted == wasDeleted;
    if (!restore && !reseal) {
      throw ApiError.invalid(
        'a trashed item can only be restored or re-sealed',
      );
    }
  }
  final revision = cur?['revision'] as int? ?? 0;
  if (ifMatch != revision) throw conflict();
  final now = deps.clock.now();
  final stored = Item(
    id: input.id,
    type: input.type,
    orgId: input.orgId,
    folderId: input.folderId,
    schemaVersion: input.schemaVersion,
    revision: revision + 1,
    deleted: input.deleted,
    meta: input.meta,
    secret:
        input.secret ??
        (storedSecret == null ? null : Envelope.fromJson(storedSecret)),
    createdAt: cur == null ? now : parseIso(cur['created_at'] as String),
    updatedAt: now,
    updatedBy: auth.userId,
    updatedDevice: auth.deviceId,
    extra: input.extra,
  );
  final text = jsonEncode(stored.toJson());
  final size = utf8.encode(text).length;
  final curSize = cur?['size'] as int? ?? 0;
  // With item history on, an update keeps the replaced version as a revision.
  final addsRevision = cur != null && deps.features.enabled(Flag.itemHistory);
  // Only a growing write, or an update that adds a revision, can exceed the quota.
  if (addsRevision || size > curSize) {
    final personal = input.scope == ItemScope.personal;
    await checkQuota(
      tx,
      ownerUserId: personal ? auth.userId : null,
      orgId: personal ? null : input.orgId,
      itemId: input.id,
      newSize: addsRevision ? curSize + size : size,
      max: personal ? deps.config.maxVaultSize : deps.config.maxOrgSize,
    );
  }
  if (input.scope == ItemScope.org &&
      (input.type == 'folder'
          ? cur == null || folderChanged || wasDeleted != input.deleted
          : folderChanged)) {
    await bumpOrgSeq(tx); // the org block lists folders and where items live
  }
  final params = {
    'id': input.id,
    'owner': input.scope == ItemScope.personal ? auth.userId : null,
    'org': input.orgId,
    'type': input.type,
    'folder': input.folderId,
    'rev': revision + 1,
    'deleted': input.deleted,
    'body': text,
    'size': size,
    'at': iso(now),
    'seq': seq,
  };
  if (cur == null) {
    await tx.execute(
      'INSERT INTO items (id, owner_user_id, org_id, type, folder_id, revision, deleted, purged, body, size, created_at, updated_at, seq) '
      'VALUES (@id, @owner, @org, @type, @folder, @rev, @deleted, 0, @body, @size, @at, @at, @seq)',
      params,
    );
  } else {
    await tx.execute(
      'UPDATE items SET folder_id = @folder, revision = @rev, deleted = @deleted, body = @body, size = @size, '
      'updated_at = @at, seq = @seq WHERE id = @id',
      {...params}
        ..remove('owner')
        ..remove('org')
        ..remove('type'),
    );
  }
  if (addsRevision) {
    await tx.execute(
      'INSERT INTO item_revisions (item_id, revision, body, size, created_at) VALUES (@i, @r, @b, @z, @t)',
      {
        'i': input.id,
        'r': revision,
        'b': cur['body'],
        'z': cur['size'],
        't': iso(now),
      },
    );
    await pruneRevisions(
      tx,
      input.id,
      (await retentionFor(tx, deps.config, input.orgId)).maxVersions,
    );
  }
  final at = [input.id, ?input.folderId]; // one audit event per write
  final (action, targets) = cur == null
      ? ('item.created', at)
      : !wasDeleted && input.deleted
      ? ('item.deleted', at)
      : wasDeleted && !input.deleted
      ? ('item.restored', at)
      : folderChanged
      ? (
          'item.moved',
          [
            input.id,
            cur['folder_id'] as String? ?? 'root',
            input.folderId ?? 'root',
          ],
        )
      : ('item.updated', at);
  await deps.audit.append(
    tx,
    scope: input.scope == ItemScope.personal
        ? AuditScope.user(auth.userId)
        : AuditScope.org(input.orgId!),
    action: action,
    actorUser: auth.userId,
    actorDevice: auth.deviceId,
    ip: ip,
    targetIds: targets,
  );
  return stored;
}

/// Org writes: parent and cycle (400), edit on the new and the old parent (403; root: a confirmed
/// owner or admin), a folder move priced like an ACL change (403 for a gain the mover lacks; lost readers queued
/// for rotation), keyIds at max(current, 1) of the item's folder (400). A re-seal of a trashed item therefore
/// needs the current key version and edit.
Future<void> checkOrgWrite(
  Tx tx,
  AuthContext auth,
  Item input,
  Map<String, Object?>? cur,
) async {
  final org = (await loadOrg(tx, input.orgId!))!;
  final isFolder = input.type == 'folder';
  final parent = input.folderId;
  if (parent != null && !org.folders.containsKey(parent)) {
    throw ApiError.invalid('folderId must be a folder of this organization');
  }
  if (!isFolder && parent == null) {
    throw ApiError.invalid('org items live in a folder');
  }
  final seen = <String>{};
  for (
    String? at = parent;
    isFolder && at != null && seen.add(at);
    at = org.parentOf(at)
  ) {
    if (at == input.id) {
      throw ApiError.invalid('a folder cannot move under itself');
    }
  }
  bool canEdit(String? folderId) => folderId == null
      ? org.members[auth.userId]!.isAdmin
      : permissionsOf(org, auth.userId, folderId).contains(Permission.edit);
  final oldParent = cur?['folder_id'] as String?;
  if (!canEdit(parent) ||
      (cur != null && oldParent != parent && !canEdit(oldParent))) {
    throw ApiError(ApiErrorCode.forbidden, 'You need edit on this folder.');
  }
  if (isFolder && cur != null && oldParent != parent) {
    // a move changes inherited entries: priced like an ACL change
    final after = org.withParent(input.id, parent);
    if (!org.members[auth.userId]!.isAdmin) {
      checkNoEscalation(org, after, auth.userId); // 403
    }
    await recordRotations(tx, input.orgId!, org, after, 'folder_moved');
  }
  final keyFolder = input.keyFolderId!;
  final version = max(await currentKeyVersion(tx, keyFolder), 1);
  if (!sealedWithFolderKeys(
    input.meta?.keyId,
    input.secret?.keyId,
    keyFolder,
    version,
  )) {
    throw ApiError.invalid(
      'payloads must use the folder keys at version $version',
    );
  }
}

/// Keeps the [max] newest revisions of [itemId] (0: all).
Future<void> pruneRevisions(Tx tx, String itemId, int max) async {
  if (max == 0) return;
  final kept = await tx.query(
    'SELECT revision FROM item_revisions WHERE item_id = @i ORDER BY revision DESC LIMIT 1 OFFSET @k',
    {'i': itemId, 'k': max - 1},
  );
  if (kept.isEmpty) return;
  await tx.execute(
    'DELETE FROM item_revisions WHERE item_id = @i AND revision < @r',
    {'i': itemId, 'r': kept.single['revision']},
  );
}

// The folderId must be a live personal folder of the caller, neither the item nor below it.
Future<void> _checkPersonalFolder(Tx tx, AuthContext auth, Item input) async {
  final parent = input.folderId;
  if (parent == null) return;
  final seen = <String>{};
  for (String? at = parent; at != null && seen.add(at);) {
    if (at == input.id) {
      throw ApiError.invalid('a folder cannot move under itself');
    }
    final r = (await tx.query(
      'SELECT owner_user_id, type, purged, folder_id FROM items WHERE id = @id',
      {'id': at},
    )).firstOrNull;
    if (at == parent &&
        (r == null ||
            r['owner_user_id'] != auth.userId ||
            r['type'] != 'folder' ||
            r['purged'] == 1)) {
      throw ApiError.invalid('folderId must be one of your folders');
    }
    at = r?['folder_id'] as String?;
  }
}

/// Trashed: deleted, or a folder of its chain deleted (seen-set: a stored loop never hangs).
Future<bool> isTrashed(
  Tx tx, {
  required bool deleted,
  required String? folderId,
}) async {
  if (deleted) return true;
  final seen = <String>{};
  for (String? at = folderId; at != null && seen.add(at);) {
    final r = (await tx.query(
      'SELECT deleted, folder_id FROM items WHERE id = @id',
      {'id': at},
    )).firstOrNull;
    if (r == null) return false;
    if (r['deleted'] == 1) return true;
    at = r['folder_id'] as String?;
  }
  return false;
}

/// Throws payloadTooLarge when the scope's other items, its revisions and [newSize] exceed [max].
/// [newSize] counts the current size too when the update adds a revision.
Future<void> checkQuota(
  Tx tx, {
  String? ownerUserId,
  String? orgId,
  required String itemId,
  required int newSize,
  required int max,
}) async {
  if (max == 0) return;
  final (column, owner) = ownerUserId != null
      ? ('owner_user_id', ownerUserId)
      : ('org_id', orgId!);
  final items =
      (await tx.query(
            'SELECT CAST(COALESCE(SUM(size), 0) AS BIGINT) AS s FROM items WHERE $column = @o AND id <> @id',
            {'o': owner, 'id': itemId},
          )).single['s']
          as int;
  final revisions =
      (await tx.query(
            'SELECT CAST(COALESCE(SUM(r.size), 0) AS BIGINT) AS s FROM item_revisions r '
            'JOIN items i ON i.id = r.item_id WHERE i.$column = @o',
            {'o': owner},
          )).single['s']
          as int;
  if (items + revisions + newSize > max) {
    throw ApiError(ApiErrorCode.payloadTooLarge, 'Storage quota exceeded.');
  }
}
