// SPDX-License-Identifier: Apache-2.0
enum Permission { view, connect, reveal, edit, manage }

enum OrgRole { owner, admin, member }

enum MemberStatus { accepted, confirmed }

enum PrincipalType { user, team }

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
  final Set<Permission>
  permissions; // entry: its allow · role: all · denied: what the deny removed
}

class Explanation {
  const Explanation(this.effective, this.steps);
  final Set<Permission> effective;
  final List<ExplanationStep> steps;
}

/// reveal ⇒ connect ⇒ view; edit ⇒ view; manage ⇒ view.
Set<Permission> expand(Set<Permission> p) => {
  ...p,
  if (p.contains(Permission.reveal)) Permission.connect,
  if (p.isNotEmpty) Permission.view,
};

/// Denying view removes everything; denying connect removes reveal.
Set<Permission> denyClosure(Set<Permission> deny) => {
  for (final d in deny)
    ...switch (d) {
      Permission.view => Permission.values,
      Permission.connect => const [Permission.connect, Permission.reveal],
      _ => [d],
    },
};

Explanation resolvePermissions({
  required OrgRole? role,
  required MemberStatus? status,
  required bool disabled,
  required String userId,
  required Set<String> teamIds,
  required String folderId,
  required String? Function(String id) parentOf,
  required Iterable<AclEntry> entries,
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
  final chain = <String>[];
  final seen = <String>{};
  for (String? at = folderId; at != null && seen.add(at); at = parentOf(at)) {
    chain.add(at); // nearest first; a stored cycle ends the walk
  }
  final byKey = {
    for (final e in entries) (e.principalType, e.principalId, e.folderId): e,
  };
  AclEntry? nearest(PrincipalType type, String id) {
    for (final f in chain) {
      final e = byKey[(type, id, f)];
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
    steps.add(
      ExplanationStep(
        StepKind.entry,
        principalType: PrincipalType.team,
        principalId: teamId,
        folderId: e.folderId,
        permissions: e.allow,
      ),
    );
  }
  final mine = nearest(PrincipalType.user, userId);
  if (mine != null) {
    allow.addAll(mine.allow);
    steps.add(
      ExplanationStep(
        StepKind.entry,
        principalType: PrincipalType.user,
        principalId: userId,
        folderId: mine.folderId,
        permissions: mine.allow,
      ),
    );
  }
  final granted = expand(allow);
  final removed = mine == null
      ? <Permission>{}
      : granted.intersection(denyClosure(mine.deny));
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
