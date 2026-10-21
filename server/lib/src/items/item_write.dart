// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:math';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/deps.dart';
import '../api/errors.dart';
import '../api/middleware.dart';
import '../audit/audit_log.dart';
import '../audit/retention_policy.dart';
import '../db/db.dart';
import '../orgs/org_access.dart';
import '../orgs/rotations.dart';

part 'item_checks.dart';

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
  Item input, {
  required AuthContext auth,
  required int ifMatch,
  String? ip,
}) async {
  // Taking the seq first makes commit order match seq order.
  final seq = await nextItemSeq(tx);
  final rows = await tx.query(
    'SELECT owner_user_id, org_id, folder_id, type, revision, deleted, purged, size, created_at, body FROM items WHERE id = @id',
    {'id': input.id},
  );
  final change = _ItemChange(input, rows.firstOrNull);
  await _checkOwnership(deps, tx, change, auth: auth);
  _checkReplaceable(change);
  if (input.scope == ItemScope.personal) {
    await _checkPersonalFolder(tx, auth, input);
  } else {
    await checkOrgWrite(tx, auth, input, row: change.row);
  }
  await _checkTrashTransition(tx, change);
  if (ifMatch != change.revision) throw change.conflict();
  final now = deps.clock.now();
  final stored = change.toStored(auth, now);
  final text = jsonEncode(stored.toJson());
  final size = utf8.encode(text).length;
  // With item history on, an update keeps the replaced version as a revision.
  final addsRevision =
      !change.isCreate && deps.features.enabled(Flag.itemHistory);
  // Only a growing write, or an update that adds a revision, can exceed the quota.
  if (addsRevision || size > change.size) {
    await _checkScopeQuota(
      deps,
      tx,
      input,
      auth: auth,
      newSize: addsRevision ? change.size + size : size,
    );
  }
  // The org block lists folders and where items live.
  if (change.movesOrgTree) await bumpOrgSeq(tx);
  await _saveRow(tx, change, {
    'id': input.id,
    'owner': input.scope == ItemScope.personal ? auth.userId : null,
    'org': input.orgId,
    'type': input.type,
    'folder': input.folderId,
    'rev': change.revision + 1,
    'deleted': input.deleted,
    'body': text,
    'size': size,
    'at': iso(now),
    'seq': seq,
  });
  if (addsRevision) await _keepReplacedRevision(deps, tx, change, now: now);
  final (action, targets) = change.auditEvent();
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

class _ItemChange {
  _ItemChange(this.input, this.row)
    : body = row == null
          ? null
          : jsonDecode(row['body'] as String) as Map<String, Object?>;

  final Item input;
  final Map<String, Object?>? row;
  final Map<String, Object?>? body;

  bool get isCreate => row == null;
  bool get wasDeleted => row?['deleted'] == 1;
  int get revision => row?['revision'] as int? ?? 0;
  int get size => row?['size'] as int? ?? 0;
  String? get oldFolderId => row?['folder_id'] as String?;
  Object? get storedSecret => body?['secret'];
  bool get folderChanged => !isCreate && oldFolderId != input.folderId;

  // Personal items always use the `user` keyId, so only org items change key.
  bool get keyChanged =>
      !isCreate && (body?['meta'] as Map?)?['keyId'] != input.meta?.keyId;

  bool get movesOrgTree =>
      input.scope == ItemScope.org &&
      (input.type == 'folder'
          ? isCreate || folderChanged || wasDeleted != input.deleted
          : folderChanged);

  ApiError conflict() => ApiError(
    ApiErrorCode.conflict,
    'The item changed on another device.',
    extra: {'item': body},
  );

  Item toStored(AuthContext auth, DateTime now) => Item(
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
    createdAt: isCreate ? now : parseIso(row!['created_at'] as String),
    updatedAt: now,
    updatedBy: auth.userId,
    updatedDevice: auth.deviceId,
    extra: input.extra,
  );

  (String, List<String>) auditEvent() {
    final at = [input.id, ?input.folderId];
    return switch ((isCreate, wasDeleted, input.deleted)) {
      (true, _, _) => ('item.created', at),
      (false, false, true) => ('item.deleted', at),
      (false, true, false) => ('item.restored', at),
      _ when folderChanged => (
        'item.moved',
        [input.id, oldFolderId ?? 'root', input.folderId ?? 'root'],
      ),
      _ => ('item.updated', at),
    };
  }
}

Future<void> _saveRow(
  Tx tx,
  _ItemChange change,
  Map<String, Object?> params,
) async {
  if (change.isCreate) {
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
}

Future<void> _keepReplacedRevision(
  AppDeps deps,
  Tx tx,
  _ItemChange change, {
  required DateTime now,
}) async {
  final input = change.input, row = change.row!;
  await tx.execute(
    'INSERT INTO item_revisions (item_id, revision, body, size, created_at) VALUES (@i, @r, @b, @z, @t)',
    {
      'i': input.id,
      'r': change.revision,
      'b': row['body'],
      'z': row['size'],
      't': iso(now),
    },
  );
  await pruneRevisions(
    tx,
    input.id,
    (await retentionFor(tx, deps.config, input.orgId)).maxVersions,
  );
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
