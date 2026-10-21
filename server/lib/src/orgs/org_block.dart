// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:math';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../db/db.dart';
import 'org_access.dart';

typedef OrgView = ({OrgSnapshot org, Set<String> viewable, Set<String> tree});

/// [userId]'s confirmed orgs by id, each loaded once with the folders they view and the tree above them.
Future<Map<String, OrgView>> loadOrgViews(Tx tx, String userId) async {
  final views = <String, OrgView>{};
  for (final r in await tx.query(
    "SELECT org_id FROM org_members WHERE user_id = @u AND status = 'confirmed'",
    {'u': userId},
  )) {
    final org = (await loadOrg(tx, r['org_id']! as String))!;
    final viewable = org.viewable(userId);
    views[org.orgId] = (
      org: org,
      viewable: viewable,
      tree: org.tree(userId, viewable: viewable),
    );
  }
  return views;
}

/// One branch per confirmed org: non-folder items in viewable folders, folder items of the tree.
Future<List<({int seq, String id, String? body})>> visibleOrgItems(
  Tx tx,
  Map<String, OrgView> views,
  int cursor, {
  int? limit,
}) async {
  final params = <String, Object?>{'c': cursor};
  final visible = _visibleClause(params, views);
  if (visible == null) return [];
  final rows = await tx.query(
    'SELECT seq, id, body FROM items WHERE seq > @c AND $visible '
    'ORDER BY seq${limit == null ? '' : ' LIMIT $limit'}',
    params,
  );
  return [
    for (final row in rows)
      (
        seq: row['seq']! as int,
        id: row['id']! as String,
        body: row['body'] as String?,
      ),
  ];
}

/// The ids of the items [visibleOrgItems] returns from cursor 0.
Future<List<String>> visibleOrgItemIds(
  Tx tx,
  Map<String, OrgView> views,
) async {
  final params = <String, Object?>{'c': 0};
  final visible = _visibleClause(params, views);
  if (visible == null) return [];
  return [
    for (final row in await tx.query(
      'SELECT id FROM items WHERE seq > @c AND $visible',
      params,
    ))
      row['id']! as String,
  ];
}

// The OR of one branch per org with a tree, its ids put in params; null when no org has a tree.
String? _visibleClause(
  Map<String, Object?> params,
  Map<String, OrgView> views,
) {
  final branches = <String>[];
  for (final (i, view) in views.values.indexed) {
    if (view.tree.isEmpty) continue;
    params['o$i'] = view.org.orgId;
    final viewable = _inList(params, 'v${i}_', view.viewable);
    final tree = _inList(params, 't${i}_', view.tree);
    branches.add(
      "(org_id = @o$i AND ((type <> 'folder' AND folder_id IN $viewable) "
      "OR (type = 'folder' AND id IN $tree)))",
    );
  }
  if (branches.isEmpty) return null;
  return '(${branches.join(' OR ')})';
}

// `(@prefix0, @prefix1, ...)` with each id put in params; `(NULL)`, which matches nothing, for no id.
String _inList(
  Map<String, Object?> params,
  String prefix,
  Iterable<String> ids,
) {
  if (ids.isEmpty) return '(NULL)';
  final names = <String>[];
  for (final (i, id) in ids.indexed) {
    params['$prefix$i'] = id;
    names.add('@$prefix$i');
  }
  return '(${names.join(', ')})';
}

Future<OrgBlock> buildOrgBlock(
  Tx tx,
  String userId,
  Map<String, OrgView> views,
) async {
  final orgSeq =
      (await tx.query("SELECT value FROM counters WHERE name = 'org_seq'"))
              .single['value']!
          as int;
  final memberships = await tx.query(
    'SELECT o.id, o.name, o.settings, m.role, m.status FROM org_members m '
    'JOIN orgs o ON o.id = m.org_id WHERE m.user_id = @u ORDER BY o.name, o.id',
    {'u': userId},
  );
  final orgs = <OrgSummary>[];
  final members = <OrgMember>[];
  final teams = <OrgTeam>[];
  final acl = <AclRow>[];
  final folderTree = <FolderNode>[];
  final wrappedKeys = <WrappedKeyRow>[];
  final keyHistory = <WrappedKeyRow>[];
  final keyRequests = <KeyRequest>[];
  final pendingRotations = <PendingRotation>[];
  for (final m in memberships) {
    orgs.add(_summary(m));
    // An accepted member gets the org name only.
    if (m['status'] != 'confirmed') continue;
    final (:org, :viewable, :tree) = views[m['id']! as String]!;
    final admin = org.members[userId]!.isAdmin;
    members.addAll(_members(org, admin: admin));
    teams.addAll(_teams(org, userId, admin: admin));
    acl.addAll(_aclRows(org, tree, admin: admin));
    folderTree.addAll(_folderNodes(org, tree));
    wrappedKeys.addAll(
      await _viewableWrappedKeys(tx, org.orgId, userId, viewable: viewable),
    );
    keyHistory.addAll(await _keyHistory(tx, org, userId, viewable: viewable));
    if (!admin) continue;
    keyRequests.addAll(await _missingKeyRequests(tx, org));
    pendingRotations.addAll(await _pendingRotations(tx, org.orgId));
  }
  final itemIds = await visibleOrgItemIds(tx, views)
    ..sort();
  return OrgBlock(
    orgCursor: orgSeq,
    orgs: orgs,
    members: members,
    teams: teams,
    acl: acl,
    folderTree: folderTree,
    wrappedKeys: wrappedKeys,
    keyHistory: keyHistory,
    keyRequests: keyRequests,
    pendingRotations: pendingRotations,
    itemIds: itemIds,
  );
}

OrgSummary _summary(Map<String, Object?> membership) {
  final settings =
      jsonDecode(membership['settings']! as String) as Map<String, Object?>;
  return OrgSummary(
    id: membership['id']! as String,
    name: membership['name']! as String,
    role: membership['role']! as String,
    status: membership['status']! as String,
    settings: {'mascot': settings['mascot'] ?? true},
  );
}

// Status, public key and disabled flag are for admins only.
List<OrgMember> _members(OrgSnapshot org, {required bool admin}) => [
  for (final MapEntry(key: id, value: member) in org.members.entries)
    OrgMember(
      orgId: org.orgId,
      userId: id,
      email: member.email,
      role: member.role.name,
      status: admin ? member.status.name : null,
      publicKey: admin && member.publicKey != null
          ? unb64(member.publicKey!)
          : null,
      disabled: admin ? member.disabled : null,
    ),
];

List<OrgTeam> _teams(OrgSnapshot org, String userId, {required bool admin}) => [
  for (final MapEntry(key: id, value: t) in org.teams.entries)
    if (admin || t.memberIds.contains(userId))
      OrgTeam(
        orgId: org.orgId,
        id: id,
        name: t.name,
        memberIds: t.memberIds.toList()..sort(),
      ),
];

List<AclRow> _aclRows(
  OrgSnapshot org,
  Set<String> tree, {
  required bool admin,
}) => [
  for (final e in org.acl.where((e) => admin || tree.contains(e.folderId)))
    AclRow(
      orgId: org.orgId,
      folderId: e.folderId,
      principalType: e.principalType.name,
      principalId: e.principalId,
      allow: [for (final p in e.allow) p.name],
      deny: [for (final p in e.deny) p.name],
    ),
];

List<FolderNode> _folderNodes(OrgSnapshot org, Set<String> tree) => [
  for (final f in tree)
    FolderNode(orgId: org.orgId, folderId: f, parentId: org.parentOf(f)),
];

Future<List<WrappedKeyRow>> _viewableWrappedKeys(
  Tx tx,
  String orgId,
  String userId, {
  required Set<String> viewable,
}) async => [
  for (final k in await tx.query(
    'SELECT folder_id, version, meta_wrapped, secret_wrapped FROM folder_keys '
    'WHERE org_id = @o AND user_id = @u',
    {'o': orgId, 'u': userId},
  ))
    if (viewable.contains(k['folder_id']))
      WrappedKeyRow(
        folderId: k['folder_id']! as String,
        keys: WrappedFolderKeys(
          version: k['version']! as int,
          meta: Envelope.fromJson(jsonDecode(k['meta_wrapped']! as String)),
          secret: switch (k['secret_wrapped'] as String?) {
            final String secret => Envelope.fromJson(jsonDecode(secret)),
            null => null,
          },
        ),
      ),
];

Future<List<WrappedKeyRow>> _keyHistory(
  Tx tx,
  OrgSnapshot org,
  String userId, {
  required Set<String> viewable,
}) async {
  final out = <WrappedKeyRow>[];
  for (final historyRow in await tx.query(
    'SELECT folder_id, body FROM folder_key_history WHERE org_id = @o',
    {'o': org.orgId},
  )) {
    final folderId = historyRow['folder_id']! as String;
    if (!viewable.contains(folderId)) continue;
    final hasSecret = FolderKeyAccess.of(permissionsOf(org, userId, folderId))
        .hasSecret;
    final body = FolderKeyHistory.fromJson({
      ...jsonDecode(historyRow['body']! as String) as Map<String, Object?>,
      // A secret the member cannot read is never sent, so it is never parsed.
      if (!hasSecret) 'secret': null,
    });
    out.add(
      WrappedKeyRow(
        folderId: folderId,
        keys: WrappedFolderKeys(
          version: body.version,
          meta: body.meta,
          secret: body.secret,
        ),
      ),
    );
  }
  return out;
}

Future<List<KeyRequest>> _missingKeyRequests(Tx tx, OrgSnapshot org) async {
  if (org.folders.isEmpty) return [];
  final params = <String, Object?>{};
  final folders = _inList(params, 'f', org.folders.keys);
  // The rotated version where a rotation left history, else the highest version held.
  final current = {
    for (final historyRow in await tx.query(
      'SELECT folder_id, version FROM folder_key_history WHERE folder_id IN $folders',
      params,
    ))
      historyRow['folder_id']! as String: historyRow['version']! as int,
  };
  final held = <String, Map<Object?, Map<String, Object?>>>{};
  for (final keyRow in await tx.query(
    'SELECT folder_id, user_id, version, secret_wrapped FROM folder_keys WHERE folder_id IN $folders',
    params,
  )) {
    final folderId = keyRow['folder_id']! as String;
    held.putIfAbsent(folderId, () => {})[keyRow['user_id']] = keyRow;
  }
  final out = <KeyRequest>[];
  for (final folderId in org.folders.keys) {
    final keys = held[folderId] ?? const {};
    final version =
        current[folderId] ??
        keys.values.fold<int>(
          0,
          (top, keyRow) => max(top, keyRow['version']! as int),
        );
    // Nobody holds a key yet: the creator uploads the first one.
    if (version == 0) continue;
    for (final MapEntry(key: userId, value: member) in org.members.entries) {
      final access = FolderKeyAccess.of(permissionsOf(org, userId, folderId));
      if (member.status != MemberStatus.confirmed ||
          member.disabled ||
          !access.hasMeta) {
        continue;
      }
      final needsSecret = access.hasSecret;
      final keyRow = keys[userId];
      if (keyRow == null ||
          (keyRow['version']! as int) < version ||
          (needsSecret && keyRow['secret_wrapped'] == null)) {
        out.add(
          KeyRequest(
            orgId: org.orgId,
            folderId: folderId,
            userId: userId,
            version: version,
            needsSecret: needsSecret,
          ),
        );
      }
    }
  }
  return out;
}

Future<List<PendingRotation>> _pendingRotations(Tx tx, String orgId) async => [
  for (final r in await tx.query(
    'SELECT folder_id, reason, removed_user_ids, rotated_version FROM pending_rotations '
    'WHERE org_id = @o',
    {'o': orgId},
  ))
    PendingRotation(
      orgId: orgId,
      folderId: r['folder_id']! as String,
      reason: r['reason']! as String,
      removedUserIds: (jsonDecode(r['removed_user_ids']! as String) as List)
          .cast<String>(),
      rotatedVersion: r['rotated_version'] as int?,
    ),
];
