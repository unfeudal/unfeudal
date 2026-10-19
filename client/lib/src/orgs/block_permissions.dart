// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

extension OrgAdmin on OrgSummary {
  /// A confirmed owner or admin: rotates, hands keys out and writes at the org root.
  bool get isAdmin =>
      status == 'confirmed' && (role == 'owner' || role == 'admin');
}

/// Resolution of [userId] on [folderId] from a block. Role from `members`; status from the member row (admins
/// see it) or, for the caller's own row, from `orgs`. Unknown permission names are skipped.
Explanation explainFromBlock(
  OrgBlock block,
  String orgId,
  String userId,
  String folderId,
) {
  final org = block.orgs.where((o) => o.id == orgId).firstOrNull;
  final m = block.members
      .where((x) => x.orgId == orgId && x.userId == userId)
      .firstOrNull;
  final parents = {
    for (final n in block.folderTree.where((n) => n.orgId == orgId))
      n.folderId: n.parentId,
  };
  if (org == null || m == null || !parents.containsKey(folderId)) {
    return const Explanation({}, []);
  }
  Set<Permission> perms(List<String> names) => {
    for (final n in names) ?Permission.values.asNameMap()[n],
  };
  return resolvePermissions(
    role: OrgRole.values.asNameMap()[m.role],
    status: MemberStatus.values.asNameMap()[m.status ?? org.status],
    disabled: m.disabled ?? false, // admins see it; a member's own row never says disabled (a disabled user gets 401)
    userId: userId,
    teamIds: {
      for (final t in block.teams)
        if (t.orgId == orgId && t.memberIds.contains(userId)) t.id,
    },
    folderId: folderId,
    parentOf: (id) => parents[id],
    entries: [
      for (final a in block.acl.where((a) => a.orgId == orgId))
        AclEntry(
          a.folderId,
          a.principalType == 'team' ? PrincipalType.team : PrincipalType.user,
          a.principalId,
          perms(a.allow),
          perms(a.deny),
        ),
    ],
  );
}
