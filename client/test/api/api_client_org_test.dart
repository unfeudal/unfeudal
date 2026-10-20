// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/api/api_client.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/org_fixtures.dart';
import '../support/sync_harness.dart';

Future<(SyncHarness, ApiClient)> signedIn() async {
  final h = SyncHarness();
  final login = await h.signIn();
  return (
    h,
    ApiClient(h.baseUrl, h.client)
      ..accessToken = login.accessToken
      ..refreshToken = login.refreshToken,
  );
}

void main() {
  group('org, member, team, ACL and key routes', () {
    final o = testOrgId, u = newId(), t = newId(), f = newId();
    late SyncHarness h;
    late String createdOrgId;
    late OrgTeam team;
    late WrappedFolderKeys wrap;
    setUpAll(() async {
      final (harness, api) = await signedIn();
      h = harness;
      h.orgReplies['POST /orgs'] = (_) => SyncHarness.reply({
        'org': {'id': o, 'name': 'Acme', 'role': 'owner'},
      }, 201);
      h.orgReplies['POST /orgs/$o/teams'] = (b) => SyncHarness.reply({
        'team': {'id': t, 'name': b['name'], 'memberIds': b['memberIds']},
      }, 201);
      createdOrgId = (await api.orgs.create('Acme')).id;
      await api.orgs.update(o, name: 'Acme 2', settings: {'mascot': false});
      await api.orgs.setMemberRole(o, u, OrgRole.admin);
      await api.orgs.confirmMember(o, u);
      await api.orgs.removeMember(o, u);
      team = await api.orgs.createTeam(o, name: 'Ops', memberIds: [u]);
      await api.orgs.updateTeam(o, t, memberIds: const []);
      await api.orgs.deleteTeam(o, t);
      await api.orgs.putAcl(f, [
        AclEntry(f, PrincipalType.team, t, const {Permission.view}, const {}),
      ]);
      final keys = FolderKeys.generate(1), me = await memberKeys();
      wrap = await WrappedFolderKeys.wrap(
        keys,
        folderId: f,
        recipientPublicKey: me.publicKey,
        userId: u,
      );
      await api.orgs.putFolderKeys(f, version: 1, wrapped: [wrap]);
      await api.orgs.rotationDone(f);
      await api.orgs.delete(o);
    });

    test('createOrg and createTeam parse the replies', () {
      expect(createdOrgId, o);
      expect(team.orgId, o);
      expect(team.id, t);
      expect(team.memberIds, [u]);
    });

    test('each call hits its documented route', () {
      expect(h.orgCalls.map((c) => c.route), [
        'POST /orgs',
        'PUT /orgs/$o',
        'PUT /orgs/$o/members/$u',
        'POST /orgs/$o/members/$u/confirm',
        'DELETE /orgs/$o/members/$u',
        'POST /orgs/$o/teams',
        'PUT /orgs/$o/teams/$t',
        'DELETE /orgs/$o/teams/$t',
        'PUT /folders/$f/acl',
        'PUT /folders/$f/keys',
        'POST /folders/$f/rotation/done',
        'DELETE /orgs/$o',
      ]);
    });

    test('each call sends the documented body', () {
      final bodies = [for (final c in h.orgCalls) c.body];
      expect(bodies[1], {
        'name': 'Acme 2',
        'settings': {'mascot': false},
      });
      expect(bodies[2], {'role': 'admin'});
      expect(bodies[6], {'memberIds': <Object?>[]});
      expect(bodies[8], {
        'entries': [
          {
            'principalType': 'team',
            'principalId': t,
            'allow': ['view'],
            'deny': <Object?>[],
          },
        ],
      });
      expect(bodies[9], {
        'version': 1,
        'wrapped': [wrap.toJson()],
        'history': null,
      });
    });
  });

  test('invites: create, list, revoke, join', () async {
    final (h, api) = await signedIn();
    final o = testOrgId, id = newId();
    final created = {
      'id': id,
      'email': 'a@b.c',
      'role': 'member',
      'expiresAt': '2026-10-22T12:00:00.000Z',
      'link':
          'unfeudal://enroll?server=https://vault.test&token=${'t' * 43}&kind=invite',
      'file': '{}',
    };
    h.orgReplies['POST /orgs/$o/invites'] = (_) =>
        SyncHarness.reply({'invite': created, 'mailSent': true}, 201);
    h.orgReplies['GET /orgs/$o/invites'] = (_) => SyncHarness.reply({
      'invites': [
        {
          'id': id,
          'email': 'a@b.c',
          'role': 'member',
          'createdBy': newId(),
          'createdAt': '2026-10-15T12:00:00.000Z',
          'expiresAt': '2026-10-22T12:00:00.000Z',
        },
      ],
    });
    h.orgReplies['POST /invites/join'] = (_) => SyncHarness.reply({'orgId': o});
    final inv = await api.orgs.createInvite(o, email: 'a@b.c');
    expect(
      (inv.id, inv.mailSent, inv.link.startsWith('unfeudal://')),
      (id, true, true),
    );
    expect((await api.orgs.invites(o)).single.email, 'a@b.c');
    await api.orgs.revokeInvite(id);
    expect(await api.orgs.joinInvite('t' * 43), o);
    expect(h.orgCalls.first.body, {'email': 'a@b.c', 'role': 'member'});
    expect(h.orgCalls.map((c) => c.route), contains('DELETE /invites/$id'));
  });

  test('admin routes parse users, orgs and instance invites', () async {
    final (h, api) = await signedIn();
    final u = newId(), o = newId();
    h.orgReplies['GET /admin/users'] = (_) => SyncHarness.reply({
      'users': [
        {
          'id': u,
          'email': 'a@b.c',
          'disabled': false,
          'isInstanceOwner': true,
          'createdAt': '2026-10-15T12:00:00.000Z',
        },
      ],
    });
    h.orgReplies['GET /admin/orgs'] = (_) => SyncHarness.reply({
      'orgs': [
        {
          'id': o,
          'name': 'Acme',
          'owners': ['a@b.c'],
          'memberCount': 3,
          'storageBytes': 1024,
          'lastActivityAt': null,
        },
      ],
    });
    h.orgReplies['POST /admin/invites'] = (_) => SyncHarness.reply({
      'invite': {
        'id': newId(),
        'email': 'n@b.c',
        'role': null,
        'expiresAt': '2026-10-22T12:00:00.000Z',
        'link':
            'unfeudal://enroll?server=https://vault.test&token=${'t' * 43}&kind=invite',
        'file': '{}',
      },
      'mailSent': false,
    }, 201);
    final users = await api.admin.users();
    expect(
      (users.single.isInstanceOwner, users.single.createdAt),
      (true, DateTime.utc(2026, 10, 15, 12)),
    );
    final orgs = await api.admin.orgs();
    expect(orgs.single.owners, ['a@b.c']);
    expect(orgs.single.storageBytes, 1024);
    expect(orgs.single.lastActivityAt, null);
    expect((await api.admin.invite('n@b.c')).role, isNull);
    await api.admin.setDisabled(u, disabled: true);
    await api.admin.deleteUser(u);
    await api.admin.deleteOrg(o, 'Acme');
    expect(
      [
        for (final c in h.orgCalls)
          if (c.route.startsWith('PUT') || c.route.startsWith('DELETE')) c.body,
      ],
      [
        {'disabled': true},
        <String, Object?>{},
        {'confirmName': 'Acme'},
      ],
    );
  });

  test('read-only blocks every org and admin write; last_owner carries the org names', () async {
    final (h, api) = await signedIn();
    h.orgReplies['DELETE /orgs/$testOrgId/members/${'1' * 8}-1111-4111-8111-111111111111'] =
        (_) => SyncHarness.reply({
          'error': 'conflict',
          'message': '',
          'reason': 'last_owner',
          'orgs': ['Acme'],
        }, 409);
    final e = await api.orgs
        .removeMember(testOrgId, '${'1' * 8}-1111-4111-8111-111111111111')
        .then<Object>((_) => 'ok', onError: (Object e) => e);
    expect(
      e,
      isA<ApiException>()
          .having((x) => x.reason, 'reason', 'last_owner')
          .having((x) => x.orgs, 'orgs', ['Acme']),
    );
    api.isReadOnly = () => true;
    for (final call in <Future<Object?> Function()>[
      () => api.orgs.create('X'),
      () => api.orgs.joinInvite('t'),
      () => api.orgs.putAcl(newId(), const []),
      () => api.admin.invite('a@b.c'),
    ]) {
      await expectLater(call(), throwsA(isA<ReadOnlyException>()));
    }
    expect(
      await api.orgs
          .invites(testOrgId)
          .then((_) => 'ok', onError: (Object e) => '$e'),
      isNot(contains('ReadOnly')),
    );
  });
}
