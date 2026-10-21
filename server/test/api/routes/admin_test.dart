// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../support/fake_mailer.dart';
import '../../support/org_world.dart';
import '../../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  late FakeMailer mail;
  setUp(() async {
    mail = FakeMailer();
    s = await TestServer.start(
      env: {
        'UNFEUDAL_SMTP_HOST': 'smtp.test',
        'UNFEUDAL_SMTP_FROM': 'vault@example.org',
        // Invite mails only.
        'UNFEUDAL_FEATURE_SECURITY_EMAILS': 'false',
      },
      mailer: mail,
    );
    w = await OrgWorld.build(
      s,
      roles: {'mia': 'member', 'oscar': 'owner'},
      folders: {'prod': null},
    );
    await w.acl('prod', 'user:mia', allow: ['connect']);
    await w.keys('prod', 1, ['olivia', 'mia']);
  });
  tearDown(() => s.close());

  String user(String name) => '/api/v1/admin/users/${w.id(name)}';
  String io() => w.io.accessToken;

  test(
    'every admin route is 403 for anyone else, before the body is read',
    () async {
      final t = w['olivia'].accessToken;
      for (final r in [
        await s.get('/api/v1/admin/users', token: t),
        await s.put(user('mia'), token: t, body: 'not json'),
        await s.delete(user('mia'), token: t),
        await s.get('/api/v1/admin/orgs', token: t),
        await s.delete('/api/v1/admin/orgs/${w.orgId}', token: t, body: 'x'),
        await s.post('/api/v1/admin/invites', token: t, body: 'x'),
        await s.get('/api/v1/admin/invites', token: t),
      ]) {
        expect(r.status, 403);
      }
      expect((await s.get('/api/v1/admin/users')).status, 401);
    },
  );

  test('users: every account by email', () async {
    final r = await s.get('/api/v1/admin/users', token: io());
    final users = (r.body['users']! as List).cast<Map<String, Object?>>();
    expect(users.map((u) => u['email']), [
      'mia@example.org',
      'olivia@example.org',
      'oscar@example.org',
      'owner@example.org',
    ]);
    expect(users.first.keys, [
      'id',
      'email',
      'disabled',
      'isInstanceOwner',
      'createdAt',
    ]);
    expect(users.last['isInstanceOwner'], isTrue);
  });

  test('disable: IO 403, unknown 404, non-boolean 400', () async {
    expect(
      (await s.put(
        '/api/v1/admin/users/${w.io.userId}',
        token: io(),
        body: {'disabled': true},
      )).status,
      403,
    );
    expect(
      (await s.put(
        '/api/v1/admin/users/${newId()}',
        token: io(),
        body: {'disabled': true},
      )).status,
      404,
    );
    expect(
      (await s.put(user('mia'), token: io(), body: {'disabled': 'yes'})).status,
      400,
    );
  });

  test('disable: the last owner is 409 with the org names', () async {
    expect(
      (await s.put(
        user('oscar'),
        token: io(),
        body: {'disabled': true},
      )).status,
      204,
    );
    final last = await s.put(
      user('olivia'),
      token: io(),
      body: {'disabled': true},
    );
    expect(last.status, 409);
    expect(last.body['reason'], 'last_owner');
    expect(last.body['orgs'], ['Acme']);
  });

  test('disable: sessions stop, keys rotate and memberships stay', () async {
    await s.put(user('oscar'), token: io(), body: {'disabled': true});
    final seq = await w.orgSeq();
    expect(
      (await s.put(user('mia'), token: io(), body: {'disabled': true})).status,
      204,
    );
    expect(
      (await s.get('/api/v1/sync', token: w['mia'].accessToken)).body['reason'],
      'device_revoked',
    );
    final row = (await s.db.query(
      'SELECT reason, removed_user_ids FROM pending_rotations',
    )).single;
    expect(
      row['reason'],
      'user_disabled',
      reason: 'merged with oscar\'s earlier loss',
    );
    expect(
      jsonDecode(row['removed_user_ids']! as String),
      [w.id('mia'), w.id('oscar')]..sort(),
      reason: 'merged with oscar\'s earlier loss',
    );
    expect(await w.orgSeq(), seq + 1);
    expect(
      await w.count('org_members', 'user_id = @u', {'u': w.id('mia')}),
      1,
      reason: 'memberships stay',
    );
  });

  test('enable: a re-enabled account syncs again', () async {
    await s.put(user('mia'), token: io(), body: {'disabled': true});
    expect(
      (await s.put(user('mia'), token: io(), body: {'disabled': false})).status,
      204,
    );
    expect(
      (await s.get('/api/v1/sync', token: w['mia'].accessToken)).status,
      200,
    );
  });

  test('delete user: the Instance Owner is 403', () async {
    expect(
      (await s.delete(
        '/api/v1/admin/users/${w.io.userId}',
        token: io(),
      )).status,
      403,
    );
  });

  test('delete user: an unknown id is 404', () async {
    expect(
      (await s.delete('/api/v1/admin/users/${newId()}', token: io())).status,
      404,
    );
  });

  test('delete user: a last owner is 409 with the org names', () async {
    await s.db.execute('UPDATE users SET disabled = 1 WHERE id = @u', {
      'u': w.id('oscar'),
    });
    final last = await s.delete(user('olivia'), token: io());
    expect(last.status, 409);
    expect(last.body['orgs'], ['Acme']);
  });

  test('delete user: anyone else is gone and their orgs rotate', () async {
    expect((await s.delete(user('mia'), token: io())).status, 204);
    expect(await w.count('users', 'id = @u', {'u': w.id('mia')}), 0);
    expect(
      (await s.db.query('SELECT reason FROM pending_rotations'))
          .single['reason'],
      'user_deleted',
    );
  });

  test('admin routes return metadata only', () async {
    final host = await w.item(w['olivia'], folder: 'prod');
    await w.put(w['olivia'], host, 0);
    final r = await s.get('/api/v1/admin/orgs', token: io());
    final org = ((r.body['orgs']! as List).single as Map<String, Object?>);
    expect(org.keys, [
      'id',
      'name',
      'owners',
      'memberCount',
      'storageBytes',
      'lastActivityAt',
    ]);
    expect(org['name'], 'Acme');
    expect(org['owners'], ['olivia@example.org', 'oscar@example.org']);
    expect(org['memberCount'], 3);
    final sizes = await s.db.query(
      'SELECT CAST(COALESCE(SUM(size), 0) AS BIGINT) AS n FROM items WHERE org_id = @o',
      {'o': w.orgId},
    );
    expect(org['storageBytes'], sizes.single['n']);
    expect(org['lastActivityAt'], iso(s.clock.now()));
    expect(jsonEncode(r.json), isNot(contains('"meta"')));
  });

  test('delete org: exact name, unknown 404, then gone', () async {
    final path = '/api/v1/admin/orgs/${w.orgId}';
    expect(
      (await s.delete(path, token: io(), body: {'confirmName': 'acme'})).status,
      400,
    );
    expect(
      (await s.delete(
        '/api/v1/admin/orgs/${newId()}',
        token: io(),
        body: {'confirmName': 'Acme'},
      )).status,
      404,
    );
    final seq = await w.orgSeq();
    expect(
      (await s.delete(path, token: io(), body: {'confirmName': 'Acme'})).status,
      204,
    );
    expect((await w.count('orgs'), await w.orgSeq()), (0, seq + 1));
  });

  test('instance invites: role null, mailed in the IO\'s locale, listed apart from org invites', () async {
    await s.db.execute("UPDATE users SET locale = 'fr' WHERE id = @u", {
      'u': w.io.userId,
    });
    final r = await s.post(
      '/api/v1/admin/invites',
      token: io(),
      body: {'email': 'new@example.org'},
    );
    expect(
      (r.status, (r.body['invite']! as Map)['role'], r.body['mailSent']),
      (201, null, true),
    );
    expect(
      (mail.sent.single.to, mail.sent.single.locale),
      ('new@example.org', 'fr'),
    );
    await s.post(
      '/api/v1/orgs/${w.orgId}/invites',
      token: w['olivia'].accessToken,
      body: {'email': 'org@example.org'},
    );
    final list = await s.get('/api/v1/admin/invites', token: io());
    final rows = (list.body['invites']! as List).cast<Map<String, Object?>>();
    expect(rows.map((i) => i['email']), ['new@example.org']);
    expect(rows.single.keys, [
      'id',
      'email',
      'createdBy',
      'createdAt',
      'expiresAt',
    ]);
    expect(
      (await s.post(
        '/api/v1/admin/invites',
        token: io(),
        body: {'email': 'bad'},
      )).status,
      400,
    );
  });
}
