// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../db/db.dart';
import 'org_access.dart' hide OrgTeam;

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
/// ponytail: one query per org; group them if a member of many orgs shows up in profiles.
Future<List<({int seq, String id, String? body})>> visibleOrgItems(
  Tx tx,
  Map<String, OrgView> views,
  int cursor, {
  int? limit,
  bool idsOnly = false,
}) async {
  final out = <({int seq, String id, String? body})>[];
  for (final view in views.values) {
    final org = view.org;
    final viewable = view.viewable.toList(), tree = view.tree.toList();
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
    final orgId = m['id']! as String;
    final settings =
        jsonDecode(m['settings']! as String) as Map<String, Object?>;
    orgs.add(
      OrgSummary(
        id: orgId,
        name: m['name']! as String,
        role: m['role']! as String,
        status: m['status']! as String,
        settings: {'mascot': settings['mascot'] ?? true},
      ),
    );
    if (m['status'] != 'confirmed') continue; // accepted: the org name only
    final (:org, :viewable, :tree) = views[orgId]!;
    final admin = org.members[userId]!.isAdmin;
    for (final MapEntry(key: id, value: x) in org.members.entries) {
      members.add(
        OrgMember(
          orgId: orgId,
          userId: id,
          email: x.email,
          role: x.role.name,
          status: admin ? x.status.name : null,
          publicKey: admin && x.publicKey != null ? unb64(x.publicKey!) : null,
          disabled: admin ? x.disabled : null,
        ),
      );
    }
    for (final MapEntry(key: id, value: t) in org.teams.entries) {
      if (admin || t.memberIds.contains(userId)) {
        teams.add(
          OrgTeam(
            orgId: orgId,
            id: id,
            name: t.name,
            memberIds: t.memberIds.toList()..sort(),
          ),
        );
      }
    }
    for (final e in org.acl.where((e) => admin || tree.contains(e.folderId))) {
      acl.add(
        AclRow(
          orgId: orgId,
          folderId: e.folderId,
          principalType: e.principalType.name,
          principalId: e.principalId,
          allow: [for (final p in e.allow) p.name],
          deny: [for (final p in e.deny) p.name],
        ),
      );
    }
    for (final f in tree) {
      folderTree.add(
        FolderNode(orgId: orgId, folderId: f, parentId: org.parentOf(f)),
      );
    }
    for (final k in await tx.query(
      'SELECT folder_id, version, meta_wrapped, secret_wrapped FROM folder_keys '
      'WHERE org_id = @o AND user_id = @u',
      {'o': orgId, 'u': userId},
    )) {
      final f = k['folder_id']! as String;
      if (!viewable.contains(f)) continue; // only what the caller can view now
      final secret = k['secret_wrapped'] as String?;
      wrappedKeys.add(
        WrappedKeyRow(
          folderId: f,
          keys: WrappedFolderKeys(
            version: k['version']! as int,
            meta: Envelope.fromJson(jsonDecode(k['meta_wrapped']! as String)),
            secret: secret == null
                ? null
                : Envelope.fromJson(jsonDecode(secret)),
          ),
        ),
      );
    }
    for (final h in await tx.query(
      'SELECT folder_id, body FROM folder_key_history WHERE org_id = @o',
      {'o': orgId},
    )) {
      final f = h['folder_id']! as String;
      if (!viewable.contains(f)) continue;
      final hasSecret = FolderKeyAccess.of(permissionsOf(org, userId, f))
          .hasSecret;
      final body = FolderKeyHistory.fromJson({
        ...jsonDecode(h['body']! as String) as Map<String, Object?>,
        // A secret the member cannot read is never sent, so it is never parsed.
        if (!hasSecret) 'secret': null,
      });
      keyHistory.add(
        WrappedKeyRow(
          folderId: f,
          keys: WrappedFolderKeys(
            version: body.version,
            meta: body.meta,
            secret: body.secret,
          ),
        ),
      );
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
        final access = FolderKeyAccess.of(permissionsOf(org, u, f));
        if (x.status != MemberStatus.confirmed ||
            x.disabled ||
            !access.hasMeta) {
          continue;
        }
        final needsSecret = access.hasSecret;
        final k = held[u];
        if (k == null ||
            (k['version']! as int) < current ||
            (needsSecret && k['secret_wrapped'] == null)) {
          keyRequests.add(
            KeyRequest(
              orgId: orgId,
              folderId: f,
              userId: u,
              version: current,
              secret: needsSecret,
            ),
          );
        }
      }
    }
    for (final r in await tx.query(
      'SELECT folder_id, reason, removed_user_ids, rotated_version FROM pending_rotations '
      'WHERE org_id = @o',
      {'o': orgId},
    )) {
      pendingRotations.add(
        PendingRotation(
          orgId: orgId,
          folderId: r['folder_id']! as String,
          reason: r['reason']! as String,
          removedUserIds: (jsonDecode(r['removed_user_ids']! as String) as List)
              .cast<String>(),
          rotatedVersion: r['rotated_version'] as int?,
        ),
      );
    }
  }
  final itemIds = [
    for (final x in await visibleOrgItems(tx, views, 0, idsOnly: true)) x.id,
  ]..sort();
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
