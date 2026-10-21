// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

const prod = 'prod', db = 'db';
const ops = 'team-ops', dev = 'team-dev';
const alice = 'alice', bob = 'bob', carol = 'carol', dave = 'dave';
const teamsOf = {
  alice: {ops},
  bob: {ops, dev},
  carol: {dev},
  dave: <String>{},
};
String? parentOf(String id) => id == db ? prod : null;

const v = Permission.view,
    c = Permission.connect,
    r = Permission.reveal,
    e = Permission.edit,
    m = Permission.manage;

AclEntry team(String id, String folder, Set<Permission> allow) => AclEntry(
  folderId: folder,
  principalType: PrincipalType.team,
  principalId: id,
  allow: allow,
  deny: const {},
);
AclEntry user(
  String id,
  String folder, {
  Set<Permission> allow = const {},
  Set<Permission> deny = const {},
}) => AclEntry(
  folderId: folder,
  principalType: PrincipalType.user,
  principalId: id,
  allow: allow,
  deny: deny,
);

Explanation run(
  String who,
  String folder,
  List<AclEntry> acl, {
  OrgRole role = OrgRole.member,
  MemberStatus status = MemberStatus.confirmed,
  bool disabled = false,
  String? Function(String)? parents,
}) => resolvePermissions(
  role: role,
  status: status,
  disabled: disabled,
  userId: who,
  teamIds: teamsOf[who]!,
  folderId: folder,
  parentOf: parents ?? parentOf,
  acl: AclIndex(acl),
);

void main() {
  group('permission examples', () {
    test('1: a team entry on the parent applies to the child', () {
      expect(
        run(alice, db, [
          team(ops, prod, {v, c}),
        ]).effective,
        {v, c},
      );
    });
    test('2: two teams add up', () {
      expect(
        run(bob, prod, [
          team(ops, prod, {v, c}),
          team(dev, prod, {v, e}),
        ]).effective,
        {v, c, e},
      );
    });
    test('3: a user deny removes a team allow', () {
      expect(
        run(bob, prod, [
          team(ops, prod, {v, c, r}),
          user(bob, prod, deny: {r}),
        ]).effective,
        {v, c},
      );
    });
    test('4: a user allow on the child adds to the team allow', () {
      expect(
        run(alice, db, [
          team(ops, prod, {v}),
          user(alice, db, allow: {e}),
        ]).effective,
        {v, e},
      );
    });
    test('5: the nearest entry of a principal replaces its parent entry', () {
      expect(
        run(alice, db, [
          team(ops, prod, {v, c}),
          team(ops, db, {v}),
        ]).effective,
        {v},
      );
    });
    test('6: a child user entry replaces the parent user deny', () {
      expect(
        run(bob, db, [
          team(ops, prod, {v, c}),
          user(bob, prod, deny: {c}),
          user(bob, db, allow: {e}),
        ]).effective,
        {v, c, e},
      );
    });
    test('7: denying view removes everything', () {
      expect(
        run(carol, prod, [
          team(dev, prod, {v}),
          user(carol, prod, deny: {v}),
        ]).effective,
        isEmpty,
      );
    });
    test('8: an admin has everything, whatever the ACL', () {
      expect(
        run(dave, db, [
          user(dave, prod, deny: {v}),
        ], role: OrgRole.admin).effective,
        Permission.values.toSet(),
      );
      expect(
        run(dave, prod, const [], role: OrgRole.owner).effective,
        Permission.values.toSet(),
      );
    });
  });

  test('reveal implies connect and view; edit and manage imply view', () {
    Set<Permission> mine(
      Set<Permission> allow, [
      Set<Permission> deny = const {},
    ]) =>
        run(dave, prod, [user(dave, prod, allow: allow, deny: deny)]).effective;
    final all = Permission.values.toSet();
    expect(mine({r}), {r, c, v});
    expect(mine({e}), {e, v});
    expect(mine({m}), {m, v});
    expect(mine({}), isEmpty);
    expect(mine(all, {c}), {v, e, m});
    expect(mine(all, {v}), isEmpty);
    expect(mine(all, {e}), {v, c, r, m});
  });

  test('accepted, disabled or absent members get nothing', () {
    final acl = [
      team(ops, prod, {v, c}),
    ];
    expect(
      run(alice, prod, acl, status: MemberStatus.accepted).effective,
      isEmpty,
    );
    expect(run(alice, prod, acl, disabled: true).effective, isEmpty);
    expect(
      run(dave, prod, acl, role: OrgRole.owner, disabled: true).effective,
      isEmpty,
    );
    expect(
      resolvePermissions(
        role: null,
        status: null,
        disabled: false,
        userId: alice,
        teamIds: const {},
        folderId: prod,
        parentOf: parentOf,
        acl: AclIndex(acl),
      ).effective,
      isEmpty,
    );
  });

  test('team entries never deny', () {
    const bad = AclEntry(
      folderId: prod,
      principalType: PrincipalType.team,
      principalId: ops,
      allow: {v, c},
      deny: {c},
    );
    expect(run(alice, prod, [bad]).effective, {v, c});
  });

  test('another user\'s entry does not apply', () {
    expect(
      run(alice, prod, [
        user(bob, prod, allow: {e}),
      ]).effective,
      isEmpty,
    );
  });

  test('an ancestor cycle ends the walk instead of looping', () {
    String? loop(String id) => id == db ? prod : db;
    expect(
      run(alice, db, [
        team(ops, prod, {v}),
      ], parents: loop).effective,
      {v},
    );
  });

  test('steps explain each team entry, the user entry and the deny', () {
    final x = run(bob, db, [
      team(ops, prod, {v, c, r}),
      team(dev, db, {e}),
      user(bob, prod, deny: {r}),
    ]);
    expect(x.effective, {v, c, e});
    String names(Set<Permission> p) =>
        (p.map((x) => x.name).toList()..sort()).join(',');
    expect(
      x.steps.map(
        (s) => (s.kind, s.principalId, s.folderId, names(s.permissions)),
      ),
      [
        (StepKind.entry, dev, db, 'edit'),
        (StepKind.entry, ops, prod, 'connect,reveal,view'),
        (StepKind.entry, bob, prod, ''),
        (StepKind.denied, bob, prod, 'reveal'),
      ],
    );
  });

  test('an admin gets a single role step', () {
    expect(
      run(dave, db, const [], role: OrgRole.admin).steps.single.kind,
      StepKind.role,
    );
  });

  test('a member not yet confirmed gets a single notConfirmed step', () {
    expect(
      run(alice, db, const [], status: MemberStatus.accepted).steps.single.kind,
      StepKind.notConfirmed,
    );
  });

  test('only admin and owner roles are owner-managed', () {
    expect(OrgRole.values.where((r) => r.isOwnerManaged), [
      OrgRole.owner,
      OrgRole.admin,
    ]);
  });
}
