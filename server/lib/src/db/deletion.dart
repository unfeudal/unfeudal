// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/errors.dart';
import '../audit/audit_log.dart';
import '../auth/rate_limit.dart';
import '../orgs/org_access.dart';
import '../orgs/rotations.dart';
import 'db.dart';

/// Removes a member: team seats, user entries, keys, a pending rotation, then the membership.
/// [reason]: member_removed | member_left | user_deleted. [before] lets deleteUser load every org before any delete.
Future<void> removeMember(
  Tx tx,
  String orgId,
  String userId,
  String reason, {
  OrgSnapshot? before,
}) async {
  final org = before ?? (await loadOrg(tx, orgId))!;
  final p = {'o': orgId, 'u': userId};
  await tx.execute(
    'DELETE FROM team_members WHERE org_id = @o AND user_id = @u',
    p,
  );
  await tx.execute(
    "DELETE FROM acl_entries WHERE org_id = @o AND principal_type = 'user' AND principal_id = @u",
    p,
  );
  await tx.execute(
    'DELETE FROM folder_keys WHERE org_id = @o AND user_id = @u',
    p,
  );
  await recordRotations(tx, orgId, org, org.without(userId), reason);
  await tx.execute(
    'DELETE FROM org_members WHERE org_id = @o AND user_id = @u',
    p,
  );
  await bumpOrgSeq(tx);
}

Future<void> deleteTeam(Tx tx, String orgId, String teamId) async {
  final before = (await loadOrg(tx, orgId))!;
  final p = {'o': orgId, 't': teamId};
  await tx.execute(
    "DELETE FROM acl_entries WHERE org_id = @o AND principal_type = 'team' AND principal_id = @t",
    p,
  );
  await tx.execute(
    'DELETE FROM team_members WHERE org_id = @o AND team_id = @t',
    p,
  );
  await tx.execute('DELETE FROM teams WHERE org_id = @o AND id = @t', p);
  await recordRotations(
    tx,
    orgId,
    before,
    (await loadOrg(tx, orgId))!,
    'team_deleted',
  );
  await bumpOrgSeq(tx);
}

Future<void> deleteOrg(Tx tx, String orgId) async {
  final p = {'o': orgId};
  for (final table in [
    'folder_keys',
    'folder_key_history',
    'pending_rotations',
    'acl_entries',
    'team_members',
    'teams',
    'invites',
  ]) {
    await tx.execute('DELETE FROM $table WHERE org_id = @o', p);
  }
  await tx.execute(
    'DELETE FROM item_revisions WHERE item_id IN (SELECT id FROM items WHERE org_id = @o)',
    p,
  );
  await tx.execute('DELETE FROM items WHERE org_id = @o', p);
  await tx.execute('DELETE FROM org_members WHERE org_id = @o', p);
  await tx.execute('DELETE FROM orgs WHERE id = @o', p);
  await bumpOrgSeq(tx); // the org:<id> audit chain stays
}

/// Deletes an account: refusals, every org loaded before any delete, member removal per org, personal data.
Future<void> deleteUser(Tx tx, String userId, {AuditWrite? audit}) async {
  final user = (await tx.query(
    'SELECT email, is_instance_owner FROM users WHERE id = @u',
    {'u': userId},
  )).firstOrNull;
  if (user == null) throw ApiError.notFound();
  if (user['is_instance_owner'] == 1) {
    throw ApiError(
      ApiErrorCode.forbidden,
      'The Instance Owner cannot be deleted.',
    );
  }
  final last = await lastOwnerOrgs(tx, userId);
  if (last.isNotEmpty) throw lastOwnerError(last);
  final orgIds = [
    for (final r in await tx.query(
      'SELECT org_id FROM org_members WHERE user_id = @u ORDER BY org_id',
      {'u': userId},
    ))
      r['org_id']! as String,
  ];
  final snapshots = {
    for (final o in orgIds) o: (await loadOrg(tx, o))!,
  }; // all loaded before any delete
  for (final MapEntry(key: orgId, value: org) in snapshots.entries) {
    await audit?.call(AuditScope.org(orgId), 'member.removed', [userId]);
    await removeMember(tx, orgId, userId, 'user_deleted', before: org);
  }
  final p = {'u': userId};
  await tx.execute(
    'DELETE FROM refresh_tokens WHERE device_id IN (SELECT id FROM devices WHERE user_id = @u)',
    p,
  );
  await tx.execute('DELETE FROM devices WHERE user_id = @u', p);
  await tx.execute(
    'DELETE FROM item_revisions WHERE item_id IN (SELECT id FROM items WHERE owner_user_id = @u)',
    p,
  );
  await tx.execute('DELETE FROM items WHERE owner_user_id = @u', p);
  // every raw IP of the user: their own chain, and the events they performed in org and instance chains
  await tx.execute(
    'DELETE FROM audit_ips WHERE scope = @s OR EXISTS (SELECT 1 FROM audit_events e '
    'WHERE e.scope = audit_ips.scope AND e.seq = audit_ips.seq AND e.actor_user = @u)',
    {'s': 'user:$userId', 'u': userId},
  );
  final email = user['email']! as String;
  await tx.execute(
    "DELETE FROM login_attempts WHERE key IN (@a, @e, @ic, @m) OR key LIKE @ai ESCAPE '\\'",
    {
      'a': acctKey(email),
      'e': eventsKey(userId),
      'ic': inviteCreateKey(userId),
      'm': mailKey(userId),
      'ai': acctIpKey(
        email
            .replaceAll(r'\', r'\\')
            .replaceAll('%', r'\%')
            .replaceAll('_', r'\_'),
        '%',
      ),
    },
  );
  await tx.execute('DELETE FROM users WHERE id = @u', p);
  await audit?.call(AuditScope.instance, 'account.deleted', [userId]);
}

/// Turns [itemId] and, for a folder, its whole subtree into tombstones in the caller's transaction; an org
/// folder also loses its ACL, keys, key history and pending rotation (a personal folder has none).
Future<void> purgeItem(Tx tx, String itemId, AuditLog audit) async {
  var seq = await nextItemSeq(tx); // first statement: sync invariant
  final root = (await tx.query(
    'SELECT org_id, owner_user_id, type, purged FROM items WHERE id = @i',
    {'i': itemId},
  )).firstOrNull;
  if (root == null || root['purged'] == 1) return;
  final orgId = root['org_id'] as String?;
  final ids = [itemId];
  final seen = {itemId};
  for (var i = 0; i < ids.length; i++) {
    // breadth first; the seen-set stops a stored loop
    for (final r in await tx.query(
      'SELECT id FROM items WHERE folder_id = @f AND purged = 0',
      {'f': ids[i]},
    )) {
      if (seen.add(r['id']! as String)) ids.add(r['id']! as String);
    }
  }
  for (final (n, id) in ids.indexed) {
    if (n > 0) seq = await nextItemSeq(tx);
    final row = (await tx.query(
      'SELECT type, folder_id, body FROM items WHERE id = @i',
      {'i': id},
    )).single;
    final tomb = Item.fromJson({
      ...jsonDecode(row['body']! as String) as Map<String, Object?>,
      'deleted': true,
      'purged': true,
      'meta': null,
      'secret': null,
    });
    final text = jsonEncode(tomb.toJson());
    await tx.execute(
      'UPDATE items SET deleted = 1, purged = 1, body = @b, size = @z, seq = @q WHERE id = @i',
      {'b': text, 'z': utf8.encode(text).length, 'q': seq, 'i': id},
    );
    await tx.execute('DELETE FROM item_revisions WHERE item_id = @i', {
      'i': id,
    });
    if (orgId != null && row['type'] == 'folder') {
      for (final t in [
        'acl_entries',
        'folder_keys',
        'folder_key_history',
        'pending_rotations',
      ]) {
        await tx.execute('DELETE FROM $t WHERE folder_id = @f', {'f': id});
      }
    }
    await audit.append(
      tx,
      scope: orgId == null
          ? AuditScope.user(root['owner_user_id']! as String)
          : AuditScope.org(orgId),
      action: 'item.purged',
      targetIds: [id, if (row['folder_id'] case final String f) f],
    );
  }
  if (orgId != null && root['type'] == 'folder') await bumpOrgSeq(tx);
}
