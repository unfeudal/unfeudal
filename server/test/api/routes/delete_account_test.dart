// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../support/audit.dart';
import '../../support/items.dart';
import '../../support/org_world.dart';
import '../../support/test_server.dart';

void main() {
  late TestServer s;
  setUp(
    () async =>
        s = await TestServer.start(env: {'UNFEUDAL_LOGIN_MAX_ATTEMPTS': '3'}),
  );
  tearDown(() => s.close());
  const attacker = '198.51.100.50'; // a fresh network: setup already counted once on the default address

  Future<List<int>> authKeyOf(TestSession u) async =>
      (await deriveMasterKeys(u.password, u.bundle.salt, u.bundle.kdf)).authKey;
  Future<TestResponse> del(TestSession u, [List<int>? key]) async => s.delete(
    '/api/v1/account',
    token: u.accessToken,
    body: {'currentAuthKey': b64(key ?? await authKeyOf(u))},
    ip: attacker,
  );
  Future<int> count(String table, String column, String id) async =>
      (await s.db.query('SELECT count(*) AS n FROM $table WHERE $column = @i', {
            'i': id,
          })).single['n']!
          as int;

  test('deletes the account, its devices and personal items; its other sessions stop at once', () async {
    await s.setupOwner();
    final mia = await s.createUser('mia@example.org');
    final laptop = await s.login(
      'mia@example.org',
      testPassword,
      deviceName: 'Laptop',
    );
    final item = await testItem(mia);
    expect(
      (await s.put(
        '/api/v1/items/${item['id']}',
        token: mia.accessToken,
        body: item,
        headers: {'if-match': '0'},
      )).status,
      200,
    );
    expect((await del(mia)).status, 204);
    expect(
      (
        await count('users', 'id', mia.userId),
        await count('devices', 'user_id', mia.userId),
        await count('items', 'owner_user_id', mia.userId),
      ),
      (0, 0, 0),
    );
    final r = await s.get('/api/v1/devices', token: laptop.accessToken);
    expect((r.status, r.body['reason']), (401, 'device_revoked'));
    expect(
      await actions(s, 'instance'),
      contains(equals(['account.deleted', mia.userId])),
    );
  });

  test('the Instance Owner gets 403 before the body is read', () async {
    final o = await s.setupOwner();
    expect(
      (await s.delete(
        '/api/v1/account',
        token: o.accessToken,
        body: 'not json',
      )).status,
      403,
    );
    expect(await count('users', 'id', o.userId), 1);
  });

  test('wrong currentAuthKey is 403, malformed 400, no token 401; nothing deleted; guesses lock', () async {
    await s.setupOwner();
    final mia = await s.createUser('mia@example.org');
    expect(
      (await s.delete(
        '/api/v1/account',
        body: {'currentAuthKey': b64(List.filled(32, 1))},
      )).status,
      401,
    );
    expect(
      (await s.delete(
        '/api/v1/account',
        token: mia.accessToken,
        body: {'currentAuthKey': 'AAAA'},
        ip: attacker,
      )).status,
      400,
    );
    s.clock.advance(const Duration(seconds: 1)); // past the acct: barrier
    final wrong = await del(mia, List.filled(32, 1));
    expect(wrong.status, 403);
    expect(wrong.json, {
      'error': 'forbidden',
      'message': 'Current master password is wrong.',
    });
    s.clock.advance(const Duration(seconds: 2));
    expect((await del(mia, List.filled(32, 1))).status, 403);
    s.clock.advance(const Duration(seconds: 4));
    expect(
      (await del(mia)).status,
      429,
      reason: 'the three attempts above were counted before any key check',
    );
    expect(await count('users', 'id', mia.userId), 1);
  });

  test('the last owner of an org gets 409 with the org names; a member leaves every org', () async {
    final w = await OrgWorld.build(
      s,
      roles: {'mia': 'member'},
      folders: {'prod': null},
    );
    await w.acl('prod', 'user:mia', allow: ['view']);
    await w.keys('prod', 1, ['olivia', 'mia']);
    final r = await del(w['olivia']);
    expect(r.status, 409);
    expect(r.body['reason'], 'last_owner');
    expect(r.body['orgs'], ['Acme']);
    expect(
      await s.db.query(
        "SELECT key FROM login_attempts WHERE key LIKE 'acct:%'",
      ),
      isEmpty,
      reason: 'the key was right: the acct keys reset whatever check refuses after it',
    );
    expect(
      await w.count('org_members', 'user_id = @u', {'u': w.id('olivia')}),
      1,
    );
    expect((await del(w['mia'])).status, 204);
    expect(await w.count('org_members', 'user_id = @u', {'u': w.id('mia')}), 0);
    expect(await w.count('pending_rotations'), 1);
    expect(
      await actions(s, 'org:${w.orgId}'),
      contains(equals(['member.removed', w.id('mia')])),
    );
  });
}
