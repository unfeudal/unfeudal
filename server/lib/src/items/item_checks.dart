// SPDX-License-Identifier: AGPL-3.0-or-later
part of 'item_write.dart';

// Ownership comes first so a tombstone or a type of another account or org never shows.
Future<void> _checkOwnership(
  AppDeps deps,
  Tx tx,
  _ItemChange change, {
  required AuthContext auth,
}) async {
  final input = change.input, row = change.row;
  if (input.scope == ItemScope.personal) {
    // Another account's item, or an org item.
    if (row != null && row['owner_user_id'] != auth.userId) {
      throw ApiError(ApiErrorCode.forbidden, 'Not your item.');
    }
    return;
  }
  if (!deps.features.enabled(Flag.orgs)) {
    throw ApiError.orgsOff();
  }
  if (row != null && row['org_id'] != input.orgId) {
    throw ApiError(ApiErrorCode.forbidden, 'Not this organization\'s item.');
  }
  final member = await tx.query(
    "SELECT 1 AS x FROM org_members WHERE org_id = @o AND user_id = @u AND status = 'confirmed'",
    {'o': input.orgId, 'u': auth.userId},
  );
  if (member.isEmpty) throw ApiError.notFound();
}

void _checkReplaceable(_ItemChange change) {
  final input = change.input, row = change.row;
  // A purged item is a tombstone: no write revives it, whatever If-Match says.
  if (row != null && row['purged'] == 1) {
    throw change.conflict();
  }
  if (row != null && row['type'] != input.type) {
    throw ApiError.invalid('type is fixed at creation');
  }
  // The kept secret is sealed with the old key, so it cannot follow a move or re-seal.
  if (change.storedSecret != null &&
      input.secret == null &&
      (change.folderChanged || change.keyChanged)) {
    throw ApiError.invalid('a move or a re-seal re-seals the secret');
  }
}

Future<void> _checkTrashTransition(Tx tx, _ItemChange change) async {
  final input = change.input;
  if (change.isCreate ||
      !await isTrashed(
        tx,
        deleted: change.wasDeleted,
        folderId: change.oldFolderId,
      )) {
    return;
  }
  final restore =
      (change.wasDeleted && !input.deleted) ||
      (change.folderChanged &&
          !await isTrashed(
            tx,
            deleted: input.deleted,
            folderId: input.folderId,
          ));
  final reseal = !change.folderChanged && input.deleted == change.wasDeleted;
  if (!restore && !reseal) {
    throw ApiError.invalid('a trashed item can only be restored or re-sealed');
  }
}

Future<void> _checkScopeQuota(
  AppDeps deps,
  Tx tx,
  Item input, {
  required AuthContext auth,
  required int newSize,
}) {
  final personal = input.scope == ItemScope.personal;
  return checkQuota(
    tx,
    ownerUserId: personal ? auth.userId : null,
    orgId: personal ? null : input.orgId,
    itemId: input.id,
    newSize: newSize,
    max: personal ? deps.config.maxVaultSize : deps.config.maxOrgSize,
  );
}

/// Org writes: parent and cycle (400), edit on the new and the old parent (403; root: a confirmed
/// owner or admin), a folder move priced like an ACL change (403 for a gain the mover lacks; lost readers queued
/// for rotation), keyIds at max(current, 1) of the item's folder (400). A re-seal of a trashed item therefore
/// needs the current key version and edit.
Future<void> checkOrgWrite(
  Tx tx,
  AuthContext auth,
  Item input, {
  required Map<String, Object?>? row,
}) async {
  final org = (await loadOrg(tx, input.orgId!))!;
  final isFolder = input.type == 'folder';
  final parent = input.folderId;
  if (parent != null && !org.folders.containsKey(parent)) {
    throw ApiError.invalid('folderId must be a folder of this organization');
  }
  if (!isFolder && parent == null) {
    throw ApiError.invalid('org items live in a folder');
  }
  if (isFolder) _checkNoCycle(org, input);
  bool canEdit(String? folderId) => folderId == null
      ? org.members[auth.userId]!.isAdmin
      : permissionsOf(org, auth.userId, folderId).contains(Permission.edit);
  final oldParent = row?['folder_id'] as String?;
  if (!canEdit(parent) ||
      (row != null && oldParent != parent && !canEdit(oldParent))) {
    throw ApiError(ApiErrorCode.forbidden, 'You need edit on this folder.');
  }
  if (isFolder && row != null && oldParent != parent) {
    // a move changes inherited entries: priced like an ACL change
    final after = org.withParent(input.id, parent);
    if (!org.members[auth.userId]!.isAdmin) {
      checkNoEscalation(org, after, auth.userId); // 403
    }
    await recordRotations(
      tx,
      input.orgId!,
      before: org,
      after: after,
      reason: 'folder_moved',
    );
  }
  await _checkSealedWithCurrentKeys(tx, input);
}

void _checkNoCycle(OrgSnapshot org, Item folder) {
  final seen = <String>{};
  for (
    String? at = folder.folderId;
    at != null && seen.add(at);
    at = org.parentOf(at)
  ) {
    if (at == folder.id) {
      throw ApiError.invalid('a folder cannot move under itself');
    }
  }
}

Future<void> _checkSealedWithCurrentKeys(Tx tx, Item input) async {
  final keyFolder = input.keyFolderId!;
  final version = max(await currentKeyVersion(tx, keyFolder), 1);
  if (!sealedWithFolderKeys(
    input.meta?.keyId,
    input.secret?.keyId,
    folderId: keyFolder,
    version: version,
  )) {
    throw ApiError.invalid(
      'payloads must use the folder keys at version $version',
    );
  }
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
