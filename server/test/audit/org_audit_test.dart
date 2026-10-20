// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/audit.dart';
import '../support/org_world.dart';
import '../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  setUp(() async {
    s = await TestServer.start();
    w = await OrgWorld.build(
      s,
      roles: {'adam': 'admin', 'mia': 'member', 'max': 'member'},
      accepted: {'max'},
      folders: {'prod': null},
    );
  });
  tearDown(() => s.close());

  String org() => 'org:${w.orgId}';
  Future<List<List<String>>> since(String scope, int n) async =>
      (await actions(s, scope)).skip(n).toList();

  test(
    'org management: one member event each in org:<id>, actor = caller',
    () async {
      final (o, a) = (w['olivia'].accessToken, w['adam'].accessToken);
      final (mia, max) = (w.id('mia'), w.id('max'));
      final n = (await actions(s, org())).length;
      expect(
        (await s.put(
          '/api/v1/orgs/${w.orgId}',
          token: o,
          body: {'name': 'Acme 2'},
        )).status,
        204,
      );
      expect(
        (await s.put(
          '/api/v1/orgs/${w.orgId}/members/$mia',
          token: o,
          body: {'role': 'admin'},
        )).status,
        204,
      );
      expect(
        (await s.post(
          '/api/v1/orgs/${w.orgId}/members/$max/confirm',
          token: a,
        )).status,
        204,
      );
      expect(
        (await s.delete(
          '/api/v1/orgs/${w.orgId}/members/$mia',
          token: o,
        )).status,
        204,
      );
      expect(
        (await s.delete(
          '/api/v1/orgs/${w.orgId}/members/$max',
          token: w['max'].accessToken,
        )).status,
        204,
      );
      final events = await auditEvents(s, org());
      expect(await since(org(), n), [
        ['org.updated', w.orgId],
        ['member.role_changed', mia],
        ['member.confirmed', max],
        ['member.removed', mia],
        ['member.removed', max],
      ]);
      expect(
        [events[n].actorUser, events.last.actorUser],
        [w.id('olivia'), max],
      );
    },
  );

  test('org management: one team and ACL event each in org:<id>', () async {
    final a = w['adam'].accessToken;
    final (prod, max) = (w.folder('prod'), w.id('max'));
    await s.post('/api/v1/orgs/${w.orgId}/members/$max/confirm', token: a);
    final n = (await actions(s, org())).length;
    final team = await s.post(
      '/api/v1/orgs/${w.orgId}/teams',
      token: a,
      body: {
        'name': 'Ops',
        'memberIds': [max],
      },
    );
    final t = (team.body['team']! as Map)['id']! as String;
    expect(
      (await s.put(
        '/api/v1/orgs/${w.orgId}/teams/$t',
        token: a,
        body: {'name': 'Ops 2'},
      )).status,
      204,
    );
    expect(
      (await s.put(
        '/api/v1/folders/$prod/acl',
        token: a,
        body: {
          'entries': [
            {
              'principalType': 'team',
              'principalId': t,
              'allow': ['view'],
              'deny': <String>[],
            },
          ],
        },
      )).status,
      204,
    );
    expect(
      (await s.delete('/api/v1/orgs/${w.orgId}/teams/$t', token: a)).status,
      204,
    );
    expect(await since(org(), n), [
      ['team.created', t],
      ['team.updated', t],
      ['acl.changed', prod],
      ['team.deleted', t],
    ]);
  });

  test('org management: one key and rotation event each in org:<id>', () async {
    final (o, a) = (w['olivia'].accessToken, w['adam'].accessToken);
    final (prod, mia) = (w.folder('prod'), w.id('mia'));
    await s.put(
      '/api/v1/orgs/${w.orgId}/members/$mia',
      token: o,
      body: {'role': 'admin'},
    );
    final n = (await actions(s, org())).length;
    expect(
      (await s.put(
        '/api/v1/folders/$prod/keys',
        token: a,
        body: {
          'version': 1,
          'wrapped': [w.wrap('olivia', 'prod', 1)],
          'history': null,
        },
      )).status,
      204,
    );
    expect(
      (await s.put(
        '/api/v1/folders/$prod/keys',
        token: a,
        body: {
          'version': 2,
          'wrapped': [
            for (final u in ['olivia', 'adam', 'mia']) w.wrap(u, 'prod', 2),
          ],
          'history': w.history('prod', 2),
        },
      )).status,
      204,
    );
    // A pending rotation at version 2 is what rotation/done clears.
    await s.db.execute(
      "INSERT INTO pending_rotations (org_id, folder_id, reason, removed_user_ids, rotated_version) "
      "VALUES (@o, @f, 'member_removed', '[]', 2) ON CONFLICT (folder_id) DO NOTHING",
      {'o': w.orgId, 'f': prod},
    );
    expect(
      (await w.put(
        w['olivia'],
        await w.item(w['olivia'], id: prod, type: 'folder', keyVersion: 2),
        1,
      )).status,
      200,
    );
    expect(
      (await s.post('/api/v1/folders/$prod/rotation/done', token: a)).status,
      204,
    );
    expect(
      (await s.post('/api/v1/folders/$prod/rotation/done', token: a)).status,
      204,
      reason: 'nothing to clear: no event',
    );
    expect(await since(org(), n), [
      ['folder.keys_shared', prod],
      ['folder.keys_rotated', prod],
      ['item.updated', prod],
      ['folder.rotation_done', prod],
    ]);
  });

  test(
    'org deletion: org.deleted in the instance chain; the org chain stays',
    () async {
      final events = await auditEvents(s, org());
      final m = (await actions(s, 'instance')).length;
      expect(
        (await s.delete(
          '/api/v1/orgs/${w.orgId}',
          token: w['olivia'].accessToken,
        )).status,
        204,
      );
      expect(await since('instance', m), [
        ['org.deleted', w.orgId],
      ]);
      expect(
        await actions(s, org()),
        hasLength(events.length),
        reason: 'the org chain stays',
      );
    },
  );

  test(
    'invites: created, revoked once, accepted by join and by a new account',
    () async {
      final o = w['olivia'].accessToken;
      final n = (await actions(s, org())).length;
      final m = (await actions(s, 'instance')).length;
      final first =
          (await s.post(
                '/api/v1/orgs/${w.orgId}/invites',
                token: o,
                body: {'email': 'zoe@example.org'},
              )).body['invite']!
              as Map;
      expect(
        (await s.delete('/api/v1/invites/${first['id']}', token: o)).status,
        204,
      );
      expect(
        (await s.delete('/api/v1/invites/${first['id']}', token: o)).status,
        204,
      );
      final zoe = await s.createUser('zoe@example.org');
      final second =
          (await s.post(
                '/api/v1/orgs/${w.orgId}/invites',
                token: o,
                body: {'email': 'zoe@example.org'},
              )).body['invite']!
              as Map;
      expect(
        (await s.post(
          '/api/v1/invites/join',
          token: zoe.accessToken,
          body: {
            'token': Enrollment.parseLink(second['link']! as String).token,
          },
        )).status,
        200,
      );
      final inst =
          (await s.post(
                '/api/v1/admin/invites',
                token: w.io.accessToken,
                body: {'email': 'yan@example.org'},
              )).body['invite']!
              as Map;
      final acc = await testCrypto.create(testPassword);
      final r = await s.post(
        '/api/v1/invites/accept',
        body: {
          'token': Enrollment.parseLink(inst['link']! as String).token,
          'email': 'yan@example.org',
          'bundle': acc.bundle.toJson(),
          'authKey': b64(acc.authKey),
          'recoveryAuthKey': b64(acc.recoveryAuthKey),
          'device': testDevice(),
        },
      );
      final yan = Session.fromJson(r.json);
      expect(await since(org(), n), [
        ['invite.created', first['id']],
        ['invite.revoked', first['id']],
        ['invite.created', second['id']],
        ['invite.accepted', second['id'], zoe.userId],
      ]);
      expect(await since('instance', m), [
        ['invite.created', inst['id']],
        ['invite.accepted', inst['id'], yan.userId],
      ]);
      expect(await actions(s, 'user:${yan.userId}'), [
        ['device.added', yan.deviceId],
      ]);
      expect((await auditEvents(s, 'instance')).last.actorUser, yan.userId);
    },
  );

  test('admin: disable and enable (instance, then each org)', () async {
    final (io, mia) = (w.io.accessToken, w.id('mia'));
    final n = (await actions(s, org())).length;
    final m = (await actions(s, 'instance')).length;
    expect(
      (await s.put(
        '/api/v1/admin/users/$mia',
        token: io,
        body: {'disabled': true},
      )).status,
      204,
    );
    expect(
      (await s.put(
        '/api/v1/admin/users/$mia',
        token: io,
        body: {'disabled': false},
      )).status,
      204,
    );
    expect(await since(org(), n), [
      ['admin.user_disabled', mia],
      ['admin.user_enabled', mia],
    ]);
    expect(await since('instance', m), [
      ['admin.user_disabled', mia],
      ['admin.user_enabled', mia],
    ]);
  });

  test('admin: delete user, then delete org', () async {
    final (io, mia) = (w.io.accessToken, w.id('mia'));
    final n = (await actions(s, org())).length;
    final m = (await actions(s, 'instance')).length;
    expect((await s.delete('/api/v1/admin/users/$mia', token: io)).status, 204);
    expect(
      (await s.delete(
        '/api/v1/admin/orgs/${w.orgId}',
        token: io,
        body: {'confirmName': 'Acme'},
      )).status,
      204,
    );
    expect(await since(org(), n), [
      ['member.removed', mia],
    ]);
    expect(await since('instance', m), [
      ['account.deleted', mia],
      ['org.deleted', w.orgId],
    ]);
    expect((await auditEvents(s, 'instance')).last.actorUser, w.io.userId);
    expect(
      await actions(s, 'user:$mia'),
      isNotEmpty,
      reason: 'the user chain stays until instance retention',
    );
    expect(
      await s.db.query('SELECT seq FROM audit_ips WHERE scope = @s', {
        's': 'user:$mia',
      }),
      isEmpty,
    );
  });
}
