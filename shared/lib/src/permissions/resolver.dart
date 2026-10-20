// SPDX-License-Identifier: Apache-2.0
enum Permission { view, connect, reveal, edit, manage }

enum OrgRole { owner, admin, member }

enum MemberStatus { accepted, confirmed }

enum PrincipalType { user, team }

/// The folder keys a member's effective permissions entitle them to hold:
/// view grants the meta key, connect grants the secret key too.
enum FolderKeyAccess {
  none,
  meta,
  metaAndSecret;

  factory FolderKeyAccess.of(Set<Permission> effective) =>
      effective.contains(Permission.connect)
      ? metaAndSecret
      : effective.contains(Permission.view)
      ? meta
      : none;

  bool get hasMeta => this != none;
  bool get hasSecret => this == metaAndSecret;
}

class AclEntry {
  const AclEntry(
    this.folderId,
    this.principalType,
    this.principalId,
    this.allow,
    this.deny,
  );
  final String folderId;
  final PrincipalType principalType;
  final String principalId;
  final Set<Permission> allow;
  final Set<Permission> deny; // ignored for teams (refused at write time)
}

/// ACL entries keyed by principal and folder, built once for many [resolvePermissions] calls;
/// a later entry for the same key replaces an earlier one.
class AclIndex {
  AclIndex(Iterable<AclEntry> entries)
    : _byKey = {
        for (final e in entries)
          (e.principalType, e.principalId, e.folderId): e,
      };

  final Map<(PrincipalType, String, String), AclEntry> _byKey;

  AclEntry? entryAt(PrincipalType type, String principalId, String folderId) =>
      _byKey[(type, principalId, folderId)];
}

enum StepKind { notConfirmed, disabled, role, entry, denied }

/// One line of the "why do I have this right?" view.
class ExplanationStep {
  const ExplanationStep(
    this.kind, {
    this.principalType,
    this.principalId,
    this.folderId,
    this.permissions = const {},
  });
  final StepKind kind;
  final PrincipalType? principalType;
  final String? principalId;
  final String? folderId; // folder where the applied entry sits
  /// For an entry step its allow set, for a role step all permissions, for a
  /// denied step what the deny removed.
  final Set<Permission> permissions;
}

class Explanation {
  const Explanation(this.effective, this.steps);
  final Set<Permission> effective;
  final List<ExplanationStep> steps;
}

// reveal implies connect, and any permission implies view.
Set<Permission> _expand(Set<Permission> p) => {
  ...p,
  if (p.contains(Permission.reveal)) Permission.connect,
  if (p.isNotEmpty) Permission.view,
};

// Denying view removes everything; denying connect removes reveal.
Set<Permission> _denyClosure(Set<Permission> deny) => {
  for (final d in deny)
    ...switch (d) {
      Permission.view => Permission.values,
      Permission.connect => const [Permission.connect, Permission.reveal],
      _ => [d],
    },
};

// Nearest folder first; a stored cycle ends the walk.
List<String> _ancestry(String folderId, String? Function(String id) parentOf) {
  final chain = <String>[];
  final seen = <String>{};
  for (String? at = folderId; at != null && seen.add(at); at = parentOf(at)) {
    chain.add(at);
  }
  return chain;
}

ExplanationStep _entryStep(AclEntry entry) => ExplanationStep(
  StepKind.entry,
  principalType: entry.principalType,
  principalId: entry.principalId,
  folderId: entry.folderId,
  permissions: entry.allow,
);

Explanation resolvePermissions({
  required OrgRole? role,
  required MemberStatus? status,
  required bool disabled,
  required String userId,
  required Set<String> teamIds,
  required String folderId,
  required String? Function(String id) parentOf,
  required AclIndex acl,
}) {
  if (role == null || status != MemberStatus.confirmed) {
    return const Explanation({}, [ExplanationStep(StepKind.notConfirmed)]);
  }
  if (disabled) {
    return const Explanation({}, [ExplanationStep(StepKind.disabled)]);
  }
  final all = Permission.values.toSet();
  if (role != OrgRole.member) {
    return Explanation(all, [
      ExplanationStep(
        StepKind.role,
        principalType: PrincipalType.user,
        principalId: userId,
        permissions: all,
      ),
    ]);
  }
  final chain = _ancestry(folderId, parentOf);
  AclEntry? nearest(PrincipalType type, String id) {
    for (final f in chain) {
      final e = acl.entryAt(type, id, f);
      if (e != null) return e;
    }
    return null;
  }

  final steps = <ExplanationStep>[];
  final allow = <Permission>{};
  for (final teamId in teamIds.toList()..sort()) {
    final e = nearest(PrincipalType.team, teamId);
    if (e == null) continue;
    allow.addAll(e.allow); // teams only allow
    steps.add(_entryStep(e));
  }
  final mine = nearest(PrincipalType.user, userId);
  if (mine != null) {
    allow.addAll(mine.allow);
    steps.add(_entryStep(mine));
  }
  final granted = _expand(allow);
  final removed = mine == null
      ? <Permission>{}
      : granted.intersection(_denyClosure(mine.deny));
  if (removed.isNotEmpty) {
    steps.add(
      ExplanationStep(
        StepKind.denied,
        principalType: PrincipalType.user,
        principalId: userId,
        folderId: mine!.folderId,
        permissions: removed,
      ),
    );
  }
  return Explanation(granted.difference(removed), steps);
}
