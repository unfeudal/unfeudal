// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/errors.dart';
import '../config/config.dart';
import '../db/db.dart';

class MemberRow {
  const MemberRow({
    required this.role,
    required this.status,
    required this.disabled,
    required this.email,
    required this.publicKey,
  });

  /// Role and status only, for a caller that already passed requireAuth.
  MemberRow.fromRow(Map<String, Object?> row)
    : role = OrgRole.values.byName(row['role']! as String),
      status = MemberStatus.values.byName(row['status']! as String),
      disabled = false,
      email = '',
      publicKey = null;

  final OrgRole role;
  final MemberStatus status;
  final bool disabled;
  final String email;

  /// b64 of `bundle.publicKey`, null when the bundle has none.
  final String? publicKey;

  bool get isAdmin =>
      status == MemberStatus.confirmed && !disabled && role != OrgRole.member;
}

typedef OrgTeam = ({String name, Set<String> memberIds});
typedef OrgFolder = ({String? parentId, bool deleted});

/// One org as the permission rules see it, read in one transaction.
class OrgSnapshot {
  const OrgSnapshot({
    required this.orgId,
    required this.name,
    required this.settings,
    required this.members,
    required this.teams,
    required this.acl,
    required this.folders,
  });

  final String orgId;
  final String name;
  final Map<String, Object?> settings;
  final Map<String, MemberRow> members;
  final Map<String, OrgTeam> teams;
  final List<AclEntry> acl;

  /// Live folders: trashed ones included, purged ones out.
  final Map<String, OrgFolder> folders;

  String? parentOf(String id) => folders[id]?.parentId;

  Set<String> teamIdsOf(String userId) => {
    for (final MapEntry(:key, :value) in teams.entries)
      if (value.memberIds.contains(userId)) key,
  };

  /// [folderId] then its descendants.
  List<String> subtree(String folderId) {
    final out = <String>[];
    final seen = <String>{};
    void walk(String id) {
      if (!seen.add(id)) return;
      out.add(id);
      for (final MapEntry(:key, :value) in folders.entries) {
        if (value.parentId == id) walk(key);
      }
    }

    walk(folderId);
    return out;
  }

  /// Folders where [userId] holds `view`.
  Set<String> viewable(String userId) => {
    for (final f in folders.keys)
      if (permissionsOf(this, userId, f).contains(Permission.view)) f,
  };

  /// Viewable folders and their ancestors.
  Set<String> tree(String userId) {
    final out = <String>{};
    for (final f in viewable(userId)) {
      for (String? at = f; at != null && out.add(at); at = parentOf(at)) {}
    }
    return out;
  }

  /// The org once [userId]'s membership, team seats and user entries are gone: prices a removal first.
  OrgSnapshot without(String userId) => OrgSnapshot(
    orgId: orgId,
    name: name,
    settings: settings,
    members: {...members}..remove(userId),
    teams: {
      for (final MapEntry(:key, :value) in teams.entries)
        key: (
          name: value.name,
          memberIds: {...value.memberIds}..remove(userId),
        ),
    },
    acl: [
      for (final e in acl)
        if (!(e.principalType == PrincipalType.user && e.principalId == userId))
          e,
    ],
    folders: folders,
  );

  /// The org with [folderId] under [parentId]: prices a folder move first.
  OrgSnapshot withParent(String folderId, String? parentId) => OrgSnapshot(
    orgId: orgId,
    name: name,
    settings: settings,
    members: members,
    teams: teams,
    acl: acl,
    folders: {
      ...folders,
      folderId: (parentId: parentId, deleted: folders[folderId]!.deleted),
    },
  );
}

Set<Permission> _permissions(Object? json) => {
  for (final name in jsonDecode(json! as String) as List<Object?>)
    ...Permission.values.where((p) => p.name == name),
};

Future<OrgSnapshot?> loadOrg(Tx tx, String orgId) async {
  final org = await tx.query('SELECT name, settings FROM orgs WHERE id = @o', {
    'o': orgId,
  });
  if (org.isEmpty) return null;
  final members = {
    for (final r in await tx.query(
      'SELECT m.user_id, m.role, m.status, u.disabled, u.email, u.bundle '
      'FROM org_members m JOIN users u ON u.id = m.user_id WHERE m.org_id = @o',
      {'o': orgId},
    ))
      r['user_id']! as String: MemberRow(
        role: OrgRole.values.byName(r['role']! as String),
        status: MemberStatus.values.byName(r['status']! as String),
        disabled: r['disabled'] == 1,
        email: r['email']! as String,
        publicKey:
            (jsonDecode(r['bundle']! as String) as Map)['publicKey'] as String?,
      ),
  };
  final teams = <String, OrgTeam>{};
  for (final r in await tx.query(
    'SELECT t.id, t.name, tm.user_id FROM teams t '
    'LEFT JOIN team_members tm ON tm.team_id = t.id WHERE t.org_id = @o',
    {'o': orgId},
  )) {
    final team = teams.putIfAbsent(
      r['id']! as String,
      () => (name: r['name']! as String, memberIds: <String>{}),
    );
    if (r['user_id'] case final String userId) team.memberIds.add(userId);
  }
  final acl = [
    for (final r in await tx.query(
      'SELECT folder_id, principal_type, principal_id, allow, deny '
      'FROM acl_entries WHERE org_id = @o',
      {'o': orgId},
    ))
      AclEntry(
        r['folder_id']! as String,
        PrincipalType.values.byName(r['principal_type']! as String),
        r['principal_id']! as String,
        _permissions(r['allow']),
        _permissions(r['deny']),
      ),
  ];
  final folders = {
    for (final r in await tx.query(
      "SELECT id, folder_id, deleted FROM items WHERE org_id = @o AND type = 'folder' AND purged = 0",
      {'o': orgId},
    ))
      r['id']! as String: (
        parentId: r['folder_id'] as String?,
        deleted: r['deleted'] == 1,
      ),
  };
  return OrgSnapshot(
    orgId: orgId,
    name: org.single['name']! as String,
    settings:
        jsonDecode(org.single['settings']! as String) as Map<String, Object?>,
    members: members,
    teams: teams,
    acl: acl,
    folders: folders,
  );
}

Set<Permission> permissionsOf(OrgSnapshot org, String userId, String folderId) {
  if (!org.folders.containsKey(folderId)) return const {};
  final m = org.members[userId];
  return resolvePermissions(
    role: m?.role,
    status: m?.status,
    disabled: m?.disabled ?? false,
    userId: userId,
    teamIds: org.teamIdsOf(userId),
    folderId: folderId,
    parentOf: org.parentOf,
    entries: org.acl,
  ).effective;
}

/// No row, or an unconfirmed one when [confirmed]: 404; a missing role: 403.
Future<MemberRow> requireMember(
  Tx tx,
  String orgId,
  String userId, {
  bool confirmed = true,
  bool admin = false,
  bool owner = false,
}) async {
  final rows = await tx.query(
    'SELECT m.role, m.status, u.disabled, u.email, u.bundle FROM org_members m '
    'JOIN users u ON u.id = m.user_id WHERE m.org_id = @o AND m.user_id = @u',
    {'o': orgId, 'u': userId},
  );
  final status = rows.isEmpty
      ? null
      : MemberStatus.values.byName(rows.single['status']! as String);
  if (status == null || (confirmed && status == MemberStatus.accepted)) {
    throw ApiError(ApiErrorCode.notFound, 'No such organization.');
  }
  final r = rows.single;
  final row = MemberRow(
    role: OrgRole.values.byName(r['role']! as String),
    status: status,
    disabled: r['disabled'] == 1,
    email: r['email']! as String,
    publicKey:
        (jsonDecode(r['bundle']! as String) as Map)['publicKey'] as String?,
  );
  if ((admin && row.role == OrgRole.member) ||
      (owner && row.role != OrgRole.owner)) {
    throw ApiError(ApiErrorCode.forbidden, 'Your role does not allow this.');
  }
  return row;
}

bool _liveOwner(MemberRow m) =>
    m.role == OrgRole.owner &&
    m.status == MemberStatus.confirmed &&
    !m.disabled;

/// The user is a confirmed enabled owner and the only one.
bool isLastOwner(OrgSnapshot org, String userId) {
  final me = org.members[userId];
  return me != null &&
      _liveOwner(me) &&
      org.members.values.where(_liveOwner).length == 1;
}

/// Sorted names of the orgs where [userId] is the only confirmed enabled owner.
Future<List<String>> lastOwnerOrgs(Tx tx, String userId) async {
  final rows = await tx.query(
    'SELECT o.name FROM orgs o '
    'JOIN org_members me ON me.org_id = o.id AND me.user_id = @u '
    "AND me.role = 'owner' AND me.status = 'confirmed' "
    'JOIN users mu ON mu.id = me.user_id AND mu.disabled = 0 '
    'JOIN org_members m ON m.org_id = o.id '
    "AND m.role = 'owner' AND m.status = 'confirmed' "
    'JOIN users u ON u.id = m.user_id AND u.disabled = 0 '
    'GROUP BY o.id, o.name HAVING count(*) = 1',
    {'u': userId},
  );
  return [for (final r in rows) r['name']! as String]..sort();
}

ApiError lastOwnerError(List<String> names) => ApiError(
  ApiErrorCode.conflict,
  'The organization needs another owner first.',
  extra: {
    'reason': 'last_owner',
    'orgs': [...names]..sort(),
  },
);

/// `folder_key_history.version`, else `MAX(folder_keys.version)`, else 0.
Future<int> currentKeyVersion(Tx tx, String folderId) async {
  final history = await tx.query(
    'SELECT version FROM folder_key_history WHERE folder_id = @f',
    {'f': folderId},
  );
  if (history.isNotEmpty) return history.single['version']! as int;
  final keys = await tx.query(
    'SELECT CAST(COALESCE(MAX(version), 0) AS BIGINT) AS v FROM folder_keys WHERE folder_id = @f',
    {'f': folderId},
  );
  return keys.single['v']! as int;
}

/// `org_seq` versions the org block only.
Future<void> bumpOrgSeq(Tx tx) async {
  await tx.execute(
    "UPDATE counters SET value = value + 1 WHERE name = 'org_seq'",
  );
}

/// `max_orgs_per_user` (0: no cap) counts every membership row.
Future<void> checkMembershipCap(Tx tx, Config config, String userId) async {
  if (config.maxOrgsPerUser <= 0) return;
  final n = await tx.query(
    'SELECT count(*) AS n FROM org_members WHERE user_id = @u',
    {'u': userId},
  );
  if ((n.single['n']! as int) >= config.maxOrgsPerUser) {
    throw ApiError(
      ApiErrorCode.forbidden,
      'This account is in the maximum number of organizations.',
    );
  }
}
