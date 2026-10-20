// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/errors.dart';
import '../db/db.dart';
import 'org_access.dart';

/// For each live folder with keys, users who had view or connect before and lost it after are merged into
/// its pending_rotations row (sorted ids, reason replaced, rotated_version reset). A folder at key version 0
/// is skipped: nobody holds a key to rotate.
Future<void> recordRotations(
  Tx tx,
  String orgId, {
  required OrgSnapshot before,
  required OrgSnapshot after,
  required String reason,
}) async {
  for (final folderId in before.folders.keys.where(after.folders.containsKey)) {
    final lost = {
      for (final userId in before.members.keys)
        if (_lost(
          permissionsOf(before, userId, folderId),
          permissionsOf(after, userId, folderId),
        ))
          userId,
    };
    if (lost.isEmpty || await currentKeyVersion(tx, folderId) == 0) continue;
    final row = (await tx.query(
      'SELECT removed_user_ids FROM pending_rotations WHERE folder_id = @f',
      {'f': folderId},
    )).firstOrNull;
    final merged = {
      ...lost,
      if (row != null)
        ...(jsonDecode(row['removed_user_ids']! as String) as List)
            .cast<String>(),
    }.toList()..sort();
    final p = {'f': folderId, 'r': reason, 'ids': jsonEncode(merged)};
    if (row == null) {
      await tx.execute(
        'INSERT INTO pending_rotations (org_id, folder_id, reason, removed_user_ids, rotated_version) '
        'VALUES (@o, @f, @r, @ids, NULL)',
        {...p, 'o': orgId},
      );
    } else {
      await tx.execute(
        'UPDATE pending_rotations SET reason = @r, removed_user_ids = @ids, rotated_version = NULL WHERE folder_id = @f',
        p,
      );
    }
  }
}

/// Runs [change] against the org as loaded before it, queues the rotations it causes as [reason], bumps org_seq.
Future<void> changeOrg(
  Tx tx,
  String orgId,
  Future<void> Function(OrgSnapshot before) change, {
  required String reason,
}) async {
  final before = (await loadOrg(tx, orgId))!;
  await change(before);
  await recordRotations(
    tx,
    orgId,
    before: before,
    after: (await loadOrg(tx, orgId))!,
    reason: reason,
  );
  await bumpOrgSeq(tx);
}

bool _lost(Set<Permission> before, Set<Permission> after) {
  final (had, has) = (FolderKeyAccess.of(before), FolderKeyAccess.of(after));
  return (had.hasMeta && !has.hasMeta) || (had.hasSecret && !has.hasSecret);
}

/// Non-admin callers: every permission any member gains on any folder must be held by [callerId] on that
/// folder before the change, otherwise 403. Folders outside the changed subtree gain nothing, so checking
/// them all covers "the folder and each of its descendants".
void checkNoEscalation(OrgSnapshot before, OrgSnapshot after, String callerId) {
  for (final folderId in after.folders.keys) {
    final held = permissionsOf(before, callerId, folderId);
    for (final userId in after.members.keys) {
      final gained = permissionsOf(
        after,
        userId,
        folderId,
      ).difference(permissionsOf(before, userId, folderId));
      if (!held.containsAll(gained)) {
        throw ApiError(
          ApiErrorCode.forbidden,
          'You can only grant rights you hold on this folder.',
        );
      }
    }
  }
}
