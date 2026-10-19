// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/errors.dart';
import '../orgs/org_access.dart';
import '../orgs/rotations.dart';
import 'db.dart';

/// "Member removed". [reason]: member_removed | member_left | user_deleted. [before] lets deleteUser load
/// every org before any delete.
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

/// "User deleted": refusals, every org loaded before any delete, member removal per org, personal data.
Future<void> deleteUser(Tx tx, String userId, {required String actor}) async {
  final user = (await tx.query(
    'SELECT email, is_instance_owner FROM users WHERE id = @u',
    {'u': userId},
  )).firstOrNull;
  if (user == null) throw ApiError(ApiErrorCode.notFound, 'Not found.');
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
    // Audit hook: member.removed [userId] (org scope), before the removal
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
  await tx.execute('DELETE FROM audit_ips WHERE scope = @s', {
    's': 'user:$userId',
  });
  final email = user['email']! as String;
  await tx.execute(
    "DELETE FROM login_attempts WHERE key IN (@a, @e, @ic, @m) OR key LIKE @ai ESCAPE '\\'",
    {
      'a': 'acct:$email',
      'e': 'events:$userId',
      'ic': 'invite-create:$userId',
      'm': 'mail:$userId',
      'ai':
          'acct:${email.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}|%',
    },
  );
  await tx.execute('DELETE FROM users WHERE id = @u', p);
  // Audit hook: account.deleted [userId] (instance scope, actor)
}
