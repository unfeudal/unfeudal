// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/items.dart';
import '../support/test_server.dart';

void main() {
  late TestServer s;
  late TestSession io;
  late TestSession alice;
  late TestSession bob;
  setUp(() async {
    s = await TestServer.start(env: {'UNFEUDAL_LOGIN_MAX_ATTEMPTS': '3'});
    io = await s.setupOwner();
    alice = await s.createUser('alice@example.org');
    bob = await s.createUser('bob@example.org');
  });
  tearDown(() => s.close());
  const attacker = '198.51.100.50'; // a fresh network: setup already counted once on the default address

  Future<Map<String, Object?>> aliceItem() async {
    final item = await testItem(alice);
    expect(
      (await s.put(
        '/api/v1/items/${item['id']}',
        token: alice.accessToken,
        body: item,
        headers: {'if-match': '0'},
      )).status,
      200,
    );
    return item;
  }

  test('no route gives bob anything of alice', () async {
    final item = await aliceItem();
    expect(
      (await s.get('/api/v1/sync', token: bob.accessToken)).body['items'],
      isEmpty,
    );
    expect(
      (await s.get(
        '/api/v1/items/${item['id']}/revisions',
        token: bob.accessToken,
      )).status,
      404,
    );
    expect(
      (await s.delete(
        '/api/v1/devices/${alice.deviceId}',
        token: bob.accessToken,
      )).status,
      404,
    );
    expect(
      (await s.get(
        '/api/v1/audit?scope=user:${alice.userId}',
        token: bob.accessToken,
      )).status,
      400,
    );
    expect(
      (await s.get(
        '/api/v1/audit?scope=instance',
        token: bob.accessToken,
      )).status,
      403,
    );
    final mine = await s.get('/api/v1/audit?scope=me', token: bob.accessToken);
    expect(
      (mine.body['events']! as List).every(
        (e) => (e as Map)['actorUser'] == bob.userId,
      ),
      isTrue,
    );
  });

  test('the Instance Owner reads no personal item and no bundle of another account', () async {
    await aliceItem();
    expect(
      (await s.get('/api/v1/sync', token: io.accessToken)).body['items'],
      isEmpty,
    );
    final users = await s.get('/api/v1/admin/users', token: io.accessToken);
    expect(
      jsonEncode(users.json),
      isNot(
        anyOf(
          contains('wrappedUserKey'),
          contains('salt'),
          contains('auth_hash'),
        ),
      ),
    );
  });

  test('a stolen access token alone cannot change the password, the kit or delete the account; guesses lock', () async {
    final wrong = b64(List.filled(32, 7));
    final changed = await testCrypto.changePassword(
      alice.account,
      alice.bundle,
      'thief password',
    );
    final rotated = await testCrypto.rotateRecoveryKey(
      alice.account,
      alice.bundle,
    );
    expect(
      (await s.post(
        '/api/v1/account/password',
        token: alice.accessToken,
        ip: attacker,
        body: {
          'currentAuthKey': wrong,
          'bundle': changed.bundle.toJson(),
          'bundleVersion': 0,
          'authKey': b64(changed.authKey),
        },
      )).status,
      403,
    );
    s.clock.advance(const Duration(seconds: 1)); // past the acct: delay
    expect(
      (await s.post(
        '/api/v1/account/recovery-kit',
        token: alice.accessToken,
        ip: attacker,
        body: {
          'currentAuthKey': wrong,
          'bundle': rotated.bundle.toJson(),
          'bundleVersion': 0,
          'recoveryAuthKey': b64(rotated.recoveryAuthKey),
        },
      )).status,
      403,
    );
    s.clock.advance(const Duration(seconds: 2));
    expect(
      (await s.delete(
        '/api/v1/account',
        token: alice.accessToken,
        body: {'currentAuthKey': wrong},
        ip: attacker,
      )).status,
      403,
    );
    final right = (await deriveMasterKeys(
      alice.password,
      alice.bundle.salt,
      alice.bundle.kdf,
    )).authKey;
    s.clock.advance(const Duration(seconds: 4));
    expect(
      (await s.delete(
        '/api/v1/account',
        token: alice.accessToken,
        body: {'currentAuthKey': b64(right)},
        ip: attacker,
      )).status,
      429,
    );
    expect(
      (await s.db.query('SELECT bundle_version FROM users WHERE id = @u', {
        'u': alice.userId,
      })).single['bundle_version'],
      0,
    );
  });

  test('a disabled account cannot act, not even delete itself or change its locale', () async {
    expect(
      (await s.put(
        '/api/v1/admin/users/${bob.userId}',
        token: io.accessToken,
        body: {'disabled': true},
      )).status,
      204,
    );
    final right = (await deriveMasterKeys(
      bob.password,
      bob.bundle.salt,
      bob.bundle.kdf,
    )).authKey;
    expect(
      (await s.delete(
        '/api/v1/account',
        token: bob.accessToken,
        body: {'currentAuthKey': b64(right)},
      )).status,
      401,
    );
    expect(
      (await s.put(
        '/api/v1/account/locale',
        token: bob.accessToken,
        body: {'locale': 'fr'},
      )).status,
      401,
    );
  });
}
