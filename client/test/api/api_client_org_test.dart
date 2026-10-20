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
      createdOrgId = (await api.createOrg('Acme')).id;
      await api.updateOrg(o, name: 'Acme 2', settings: {'mascot': false});
      await api.setMemberRole(o, u, OrgRole.admin);
      await api.confirmMember(o, u);
      await api.removeMember(o, u);
      team = await api.createTeam(o, name: 'Ops', memberIds: [u]);
      await api.updateTeam(o, t, memberIds: const []);
      await api.deleteTeam(o, t);
      await api.putAcl(f, [
        AclEntry(f, PrincipalType.team, t, const {Permission.view}, const {}),
      ]);
      final keys = FolderKeys.generate(1), me = await memberKeys();
      wrap = await WrappedFolderKeys.wrap(
        keys,
        folderId: f,
        recipientPublicKey: me.publicKey,
        userId: u,
      );
      await api.putFolderKeys(f, version: 1, wrapped: [wrap]);
      await api.rotationDone(f);
      await api.deleteOrg(o);
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
    final inv = await api.createInvite(o, email: 'a@b.c');
    expect(
      (inv.id, inv.mailSent, inv.link.startsWith('unfeudal://')),
      (id, true, true),
    );
    expect((await api.orgInvites(o)).single.email, 'a@b.c');
    await api.revokeInvite(id);
    expect(await api.joinInvite('t' * 43), o);
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
    final users = await api.adminUsers();
    expect(
      (users.single.isInstanceOwner, users.single.createdAt),
      (true, DateTime.utc(2026, 10, 15, 12)),
    );
    final orgs = await api.adminOrgs();
    expect(orgs.single.owners, ['a@b.c']);
    expect(orgs.single.storageBytes, 1024);
    expect(orgs.single.lastActivityAt, null);
    expect((await api.adminInvite('n@b.c')).role, isNull);
    await api.adminSetDisabled(u, true);
    await api.adminDeleteUser(u);
    await api.adminDeleteOrg(o, 'Acme');
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
    final e = await api
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
      () => api.createOrg('X'),
      () => api.joinInvite('t'),
      () => api.putAcl(newId(), const []),
      () => api.adminInvite('a@b.c'),
    ]) {
      await expectLater(call(), throwsA(isA<ReadOnlyException>()));
    }
    expect(
      await api
          .orgInvites(testOrgId)
          .then((_) => 'ok', onError: (Object e) => '$e'),
      isNot(contains('ReadOnly')),
    );
  });
}
