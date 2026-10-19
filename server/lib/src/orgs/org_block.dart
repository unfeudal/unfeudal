// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../db/db.dart';
import 'org_access.dart';

/// One branch per confirmed org: non-folder items in viewable folders, folder items of the tree.
/// ponytail: one query per org; group them if a member of many orgs shows up in profiles.
Future<List<({int seq, String id, String? body})>> visibleOrgItems(
  Tx tx,
  String userId,
  int cursor, {
  int? limit,
  bool idsOnly = false,
}) async {
  final out = <({int seq, String id, String? body})>[];
  final orgs = await tx.query(
    "SELECT org_id FROM org_members WHERE user_id = @u AND status = 'confirmed'",
    {'u': userId},
  );
  for (final r in orgs) {
    final org = (await loadOrg(tx, r['org_id']! as String))!;
    final viewable = org.viewable(userId).toList(),
        tree = org.tree(userId).toList();
    if (tree.isEmpty) continue;
    final p = <String, Object?>{'o': org.orgId, 'c': cursor};
    String inList(String prefix, List<String> ids) {
      if (ids.isEmpty) return '(NULL)';
      for (final (i, id) in ids.indexed) {
        p['$prefix$i'] = id;
      }
      return '(${[for (var i = 0; i < ids.length; i++) '@$prefix$i'].join(', ')})';
    }

    final rows = await tx.query(
      'SELECT seq, id${idsOnly ? '' : ', body'} FROM items WHERE org_id = @o AND seq > @c AND '
      "((type <> 'folder' AND folder_id IN ${inList('v', viewable)}) OR (type = 'folder' AND id IN ${inList('t', tree)})) "
      'ORDER BY seq${limit == null ? '' : ' LIMIT $limit'}',
      p,
    );
    out.addAll([
      for (final x in rows)
        (
          seq: x['seq']! as int,
          id: x['id']! as String,
          body: x['body'] as String?,
        ),
    ]);
  }
  return out..sort((a, b) => a.seq.compareTo(b.seq));
}

Future<OrgBlock> buildOrgBlock(Tx tx, String userId) async {
  final orgSeq =
      (await tx.query("SELECT value FROM counters WHERE name = 'org_seq'"))
              .single['value']!
          as int;
  final memberships = await tx.query(
    'SELECT o.id, o.name, o.settings, m.role, m.status FROM org_members m '
    'JOIN orgs o ON o.id = m.org_id WHERE m.user_id = @u ORDER BY o.name, o.id',
    {'u': userId},
  );
  final json = <String, List<Object?>>{
    for (final k in [
      'orgs',
      'members',
      'teams',
      'acl',
      'folderTree',
      'wrappedKeys',
      'keyHistory',
      'keyRequests',
      'pendingRotations',
    ])
      k: [],
  };
  for (final m in memberships) {
    final orgId = m['id']! as String;
    final settings =
        jsonDecode(m['settings']! as String) as Map<String, Object?>;
    json['orgs']!.add({
      'id': orgId,
      'name': m['name'],
      'role': m['role'],
      'status': m['status'],
      'settings': {'mascot': settings['mascot'] ?? true},
    });
    if (m['status'] != 'confirmed') continue; // accepted: the org name only
    final org = (await loadOrg(tx, orgId))!;
    final admin = org.members[userId]!.isAdmin;
    final viewable = org.viewable(userId), tree = org.tree(userId);
    for (final MapEntry(key: id, value: x) in org.members.entries) {
      json['members']!.add({
        'orgId': orgId,
        'userId': id,
        'email': x.email,
        'role': x.role.name,
        if (admin) 'status': x.status.name,
        if (admin && x.publicKey != null) 'publicKey': x.publicKey,
        if (admin) 'disabled': x.disabled,
      });
    }
    for (final MapEntry(key: id, value: t) in org.teams.entries) {
      if (admin || t.memberIds.contains(userId)) {
        json['teams']!.add({
          'orgId': orgId,
          'id': id,
          'name': t.name,
          'memberIds': t.memberIds.toList()..sort(),
        });
      }
    }
    for (final e in org.acl.where((e) => admin || tree.contains(e.folderId))) {
      json['acl']!.add({
        'orgId': orgId,
        'folderId': e.folderId,
        'principalType': e.principalType.name,
        'principalId': e.principalId,
        'allow': [for (final p in e.allow) p.name],
        'deny': [for (final p in e.deny) p.name],
      });
    }
    for (final f in tree) {
      json['folderTree']!.add({
        'orgId': orgId,
        'folderId': f,
        'parentId': org.parentOf(f),
      });
    }
    for (final k in await tx.query(
      'SELECT folder_id, version, meta_wrapped, secret_wrapped FROM folder_keys '
      'WHERE org_id = @o AND user_id = @u',
      {'o': orgId, 'u': userId},
    )) {
      if (!viewable.contains(k['folder_id'])) {
        continue; // only what the caller can view now
      }
      json['wrappedKeys']!.add({
        'folderId': k['folder_id'],
        'version': k['version'],
        'meta': jsonDecode(k['meta_wrapped']! as String),
        'secret': k['secret_wrapped'] == null
            ? null
            : jsonDecode(k['secret_wrapped']! as String),
      });
    }
    for (final h in await tx.query(
      'SELECT folder_id, body FROM folder_key_history WHERE org_id = @o',
      {'o': orgId},
    )) {
      final f = h['folder_id']! as String;
      if (!viewable.contains(f)) continue;
      final body = jsonDecode(h['body']! as String) as Map<String, Object?>;
      json['keyHistory']!.add({
        'folderId': f,
        'version': body['version'],
        'meta': body['meta'],
        'secret': permissionsOf(org, userId, f).contains(Permission.connect)
            ? body['secret']
            : null,
      });
    }
    if (!admin) continue;
    for (final f in org.folders.keys) {
      final current = await currentKeyVersion(tx, f);
      // ponytail: one query per folder; group them if a large org shows up in profiles
      if (current == 0) {
        continue; // nobody holds a key yet: the creator uploads the first one
      }
      final held = {
        for (final k in await tx.query(
          'SELECT user_id, version, secret_wrapped FROM folder_keys WHERE folder_id = @f',
          {'f': f},
        ))
          k['user_id']: k,
      };
      for (final MapEntry(key: u, value: x) in org.members.entries) {
        final perms = permissionsOf(org, u, f);
        if (x.status != MemberStatus.confirmed ||
            x.disabled ||
            !perms.contains(Permission.view)) {
          continue;
        }
        final needsSecret = perms.contains(Permission.connect);
        final k = held[u];
        if (k == null ||
            (k['version']! as int) < current ||
            (needsSecret && k['secret_wrapped'] == null)) {
          json['keyRequests']!.add({
            'orgId': orgId,
            'folderId': f,
            'userId': u,
            'version': current,
            'secret': needsSecret,
          });
        }
      }
    }
    for (final r in await tx.query(
      'SELECT folder_id, reason, removed_user_ids, rotated_version FROM pending_rotations '
      'WHERE org_id = @o',
      {'o': orgId},
    )) {
      json['pendingRotations']!.add({
        'orgId': orgId,
        'folderId': r['folder_id'],
        'reason': r['reason'],
        'removedUserIds': jsonDecode(r['removed_user_ids']! as String),
        'rotatedVersion': r['rotated_version'],
      });
    }
  }
  final itemIds = [
    for (final x in await visibleOrgItems(tx, userId, 0, idsOnly: true)) x.id,
  ]..sort();
  return OrgBlock.fromJson({'orgCursor': orgSeq, ...json, 'itemIds': itemIds});
}
