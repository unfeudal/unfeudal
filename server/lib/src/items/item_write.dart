// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/app.dart';
import '../api/errors.dart';
import '../api/middleware.dart';
import '../config/features.dart';
import '../db/db.dart';

/// Checks 2–3 (before the transaction): the client body as an Item, server-set fields dropped.
Item parseItemInput(String pathId, Map<String, Object?> body) {
  if (body.containsKey('id') && body['id'] != pathId) {
    throw _bad('id must equal the path');
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
    item = Item.fromJson(json); // type 1–64, schemaVersion ≥ 1, deleted, meta/secret envelopes, folderId, scope, orgId iff org
  } on FormatException catch (e) {
    throw _bad('invalid item: ${e.message}');
  }
  if (personalOnlyTypes.contains(item.type) &&
      (item.scope != ItemScope.personal || item.folderId != null)) {
    throw _bad('${item.type} items are personal and have no folder');
  }
  return item;
}

ApiError _bad(String m) => ApiError(ApiErrorCode.invalidRequest, m);

/// Checks 4–12 and writes, inside the caller's transaction.
Future<Item> writeItem(
  AppDeps deps,
  Tx tx,
  AuthContext auth,
  Item input,
  int ifMatch,
) async {
  final seq =
      (await tx.query(
            "UPDATE counters SET value = value + 1 WHERE name = 'items_seq' RETURNING value",
          )).single['value']
          as int; // first statement: one seq space, commit order = seq order
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
  // Ownership first (8. and 9., first rules): a tombstone or a type of another account or org never shows.
  if (input.scope == ItemScope.personal) {
    if (cur != null && cur['owner_user_id'] != auth.userId) {
      throw ApiError(
        ApiErrorCode.forbidden,
        'Not your item.',
      ); // another account's, or an org item
    }
  } else {
    if (!deps.features.enabled(Flag.orgs)) {
      throw ApiError(
        ApiErrorCode.featureDisabled,
        'Organizations are off on this server.',
      );
    }
    if (cur != null && cur['org_id'] != input.orgId) {
      throw ApiError(ApiErrorCode.forbidden, 'Not this organization\'s item.');
    }
    final member = await tx.query(
      "SELECT 1 AS x FROM org_members WHERE org_id = @o AND user_id = @u AND status = 'confirmed'",
      {'o': input.orgId, 'u': auth.userId},
    );
    if (member.isEmpty) throw ApiError(ApiErrorCode.notFound, 'Not found.');
  }
  if (cur != null && cur['purged'] == 1) {
    throw conflict(); // 5. tombstone, whatever If-Match
  }
  if (cur != null && cur['type'] != input.type) {
    throw _bad('type is fixed at creation'); // 6.
  }
  final storedSecret = curBody?['secret'];
  final folderChanged = cur != null && cur['folder_id'] != input.folderId;
  if (storedSecret != null && input.secret == null && folderChanged) {
    throw _bad(
      'a move re-seals the secret',
    ); // 7. Org hook: a key version change re-seals too.
  }
  if (input.scope == ItemScope.personal) {
    await _checkPersonalFolder(tx, auth, input); // 8.
  } else {
    // Org hook: parent and cycle, edit permission on old and new folder, keyIds at max(current, 1).
  }
  if (cur != null &&
      await isTrashed(
        tx,
        deleted: cur['deleted'] == 1,
        folderId: cur['folder_id'] as String?,
      )) {
    // 10.
    final restore =
        (cur['deleted'] == 1 && !input.deleted) ||
        (folderChanged &&
            !await isTrashed(
              tx,
              deleted: input.deleted,
              folderId: input.folderId,
            ));
    final reseal = !folderChanged && input.deleted == (cur['deleted'] == 1); // Org hook: an org re-seal needs the current key version and edit.
    if (!restore && !reseal) {
      throw _bad('a trashed item can only be restored or re-sealed');
    }
  }
  final revision = cur?['revision'] as int? ?? 0;
  if (ifMatch != revision) throw conflict(); // 11.
  final now = deps.clock.now();
  final stored = Item(
    id: input.id,
    type: input.type,
    scope: input.scope,
    orgId: input.orgId,
    folderId: input.folderId,
    schemaVersion: input.schemaVersion,
    revision: revision + 1,
    deleted: input.deleted,
    meta: input.meta,
    secret:
        input.secret ??
        (storedSecret == null ? null : Envelope.fromJson(storedSecret)),
    createdAt: cur == null
        ? now
        : parseIso(
            cur['created_at'] as String,
          ), // set on insert, kept on update
    updatedAt: now,
    updatedBy: auth.userId,
    updatedDevice: auth.deviceId,
    extra: input.extra,
  );
  final text = jsonEncode(stored.toJson());
  final size = utf8.encode(text).length;
  final curSize = cur?['size'] as int? ?? 0;
  final addsRevision =
      cur != null &&
      deps.features.enabled(
        Flag.itemHistory,
      ); // the replaced version is kept as a revision
  if (addsRevision || size > curSize) {
    // 12. a growing write, or any update that adds a revision
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
  // Org hook: org_seq + 1 when a folder is created, moved, deleted or restored, or an item changes folder.
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
  // Revision hook: item_revisions (item_history), then audit item.created / deleted / restored / moved / updated.
  return stored;
}

/// Check 8, folder rule: folderId a live personal folder of the caller, not the item or below it.
Future<void> _checkPersonalFolder(Tx tx, AuthContext auth, Item input) async {
  final parent = input.folderId;
  if (parent == null) return;
  final seen = <String>{};
  for (String? at = parent; at != null && seen.add(at);) {
    if (at == input.id) throw _bad('a folder cannot move under itself');
    final r = (await tx.query(
      'SELECT owner_user_id, type, purged, folder_id FROM items WHERE id = @id',
      {'id': at},
    )).firstOrNull;
    if (at == parent &&
        (r == null ||
            r['owner_user_id'] != auth.userId ||
            r['type'] != 'folder' ||
            r['purged'] == 1)) {
      throw _bad('folderId must be one of your folders');
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

/// Check 12: S_items (scope, without this item) + S_revisions (every item of the scope) + newSize > max → 413.
/// newSize counts the current size too when the update adds a revision.
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
