// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

extension OrgAdmin on OrgSummary {
  /// A confirmed owner or admin: rotates, hands keys out and writes at the org root.
  bool get isAdmin =>
      isConfirmed && (knownRole == OrgRole.owner || knownRole == OrgRole.admin);
}

extension OrgBlockAdmin on OrgBlock {
  bool isAdminOf(String orgId) => orgs.any((o) => o.id == orgId && o.isAdmin);
}

/// Resolution of [userId] on [folderId] from a block. Role from `members`; status from the member row (admins
/// see it) or, for the caller's own row, from `orgs`. Unknown permission names are skipped.
Explanation explainFromBlock(
  OrgBlock block,
  String orgId, {
  required String userId,
  required String folderId,
}) {
  final index = (_indexes[block] ??= {}).putIfAbsent(
    orgId,
    () => _OrgIndex(block, orgId),
  );
  final org = index.org;
  final member = index.members[userId];
  if (org == null || member == null || !index.parents.containsKey(folderId)) {
    return const Explanation({}, []);
  }
  return resolvePermissions(
    role: member.knownRole,
    status: MemberStatus.values.asNameMap()[member.status ?? org.status],
    // Admins see the flag; a member's own row never says disabled, since a disabled user gets 401.
    disabled: member.disabled ?? false,
    userId: userId,
    teamIds: {
      for (final t in index.teams)
        if (t.memberIds.contains(userId)) t.id,
    },
    folderId: folderId,
    parentOf: (id) => index.parents[id],
    acl: index.acl,
  );
}

// Per-org lookups of a block, built on first use: a block is replaced, never changed.
final _indexes = Expando<Map<String, _OrgIndex>>();

class _OrgIndex {
  _OrgIndex(OrgBlock block, String orgId)
    : org = block.orgs.where((o) => o.id == orgId).firstOrNull,
      parents = {
        for (final n in block.folderTree.where((n) => n.orgId == orgId))
          n.folderId: n.parentId,
      },
      teams = [
        for (final t in block.teams)
          if (t.orgId == orgId) t,
      ],
      acl = AclIndex([
        for (final a in block.acl.where((a) => a.orgId == orgId)) a.entry,
      ]) {
    for (final m in block.members.where((x) => x.orgId == orgId)) {
      members.putIfAbsent(m.userId, () => m);
    }
  }

  final OrgSummary? org;
  final members = <String, OrgMember>{};
  final Map<String, String?> parents;
  final List<OrgTeam> teams;
  final AclIndex acl;
}
