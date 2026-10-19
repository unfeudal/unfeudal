// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

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
    for (final n in names) ...Permission.values.where((p) => p.name == n),
  };
  return resolvePermissions(
    role: OrgRole.values.where((r) => r.name == m.role).firstOrNull,
    status: MemberStatus.values
        .where((s) => s.name == (m.status ?? org.status))
        .firstOrNull,
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
