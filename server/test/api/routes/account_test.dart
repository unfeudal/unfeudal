// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/auth/secret_hash.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../support/test_server.dart';

void main() {
  late TestServer s;
  late TestSession owner;
  late TestSession other;
  setUp(() async {
    s = await TestServer.start();
    owner = await s.setupOwner();
    other = await s.login(owner.email, testPassword, deviceName: 'Other');
  });
  tearDown(() => s.close());

  Future<List<int>> authKeyOf(String password, AccountBundle b) async =>
      (await deriveMasterKeys(password, b.salt, b.kdf)).authKey;
  Future<Map<String, Object?>> userRow() async => (await s.db.query(
    'SELECT bundle, bundle_version, auth_hash, recovery_auth_hash FROM users',
  )).single;

  group('password', () {
    Future<Map<String, Object?>> body({
      List<int>? current,
      int version = 0,
      Map<String, Object?>? bundle,
    }) async {
      final changed = await testCrypto.changePassword(
        owner.account,
        owner.bundle,
        'new password!',
      );
      return {
        'currentAuthKey': b64(
          current ?? await authKeyOf(testPassword, owner.bundle),
        ),
        'bundle': bundle ?? changed.bundle.toJson(),
        'bundleVersion': version,
        'authKey': b64(changed.authKey),
      };
    }

    test('password change needs the current authKey and revokes every other device', () async {
      final r = await s.post(
        '/api/v1/account/password',
        token: owner.accessToken,
        body: await body(),
      );
      expect(r.status, 204);
      expect((await userRow())['bundle_version'], 1);
      expect(
        (await s.get('/api/v1/devices', token: owner.accessToken)).status,
        200,
        reason: 'caller stays signed in',
      );
      expect(
        (await s.get(
          '/api/v1/devices',
          token: other.accessToken,
        )).body['reason'],
        'device_revoked',
      );
      expect(
        (await s.post(
          '/api/v1/token/refresh',
          body: {'refreshToken': other.refreshToken},
        )).status,
        401,
      );
      expect(
        (await s.login(owner.email, 'new password!')).userId,
        owner.userId,
      );
    });

    test(
      'a wrong current authKey is 403; a malformed one is 400; nothing changes',
      () async {
        final wrong = await s.post(
          '/api/v1/account/password',
          token: owner.accessToken,
          body: await body(current: List.filled(32, 3)),
        );
        expect(wrong.status, 403);
        expect(wrong.json, {
          'error': 'forbidden',
          'message': 'Current master password is wrong.',
        });
        s.clock.advance(const Duration(seconds: 30)); // past the acct: delay
        final bad = await body();
        bad['currentAuthKey'] = 'AAAA';
        expect(
          (await s.post(
            '/api/v1/account/password',
            token: owner.accessToken,
            body: bad,
          )).status,
          400,
        );
        expect((await userRow())['bundle_version'], 0);
      },
    );

    test(
      'a bundle changing a field outside the route\'s list is 400',
      () async {
        final b = (await body())['bundle']! as Map<String, Object?>;
        for (final changed in [
          {...b, 'publicKey': b64(List.filled(32, 5))},
          {
            ...b,
            'wrappedUserKeyByRecovery': other.bundle.toJson()['wrappedUserKey'],
          },
          {...b, 'future': 1},
        ]) {
          expect(
            (await s.post(
              '/api/v1/account/password',
              token: owner.accessToken,
              body: await body(bundle: changed),
            )).status,
            400,
          );
        }
      },
    );

    test('a stale bundleVersion is 409 and nothing changes', () async {
      final r = await s.post(
        '/api/v1/account/password',
        token: owner.accessToken,
        body: await body(version: 5),
      );
      expect(r.status, 409);
      expect((await userRow())['bundle_version'], 0);
      expect(
        (await s.get('/api/v1/devices', token: other.accessToken)).status,
        200,
      );
    });

    test('needs an access token', () async {
      expect(
        (await s.post('/api/v1/account/password', body: await body())).status,
        401,
      );
    });
  });

  group('recovery', () {
    Future<Map<String, Object?>> start({String? email, List<int>? key}) async =>
        (await s.post(
          '/api/v1/account/recover/start',
          body: {
            'email': email ?? owner.email,
            'recoveryAuthKey': b64(
              key ??
                  await recoveryAuthKey(RecoveryKey.decode(owner.recoveryKey!)),
            ),
          },
        )).body;

    test(
      'recover/start proves the recovery key and returns the stored bundle',
      () async {
        expect(await start(), {
          'bundle': owner.bundle.toJson(),
          'bundleVersion': 0,
        });
      },
    );

    test(
      'unknown email, wrong key, no recovery hash or disabled: one 401',
      () async {
        final answers = [
          await start(email: 'ghost@example.org'),
          await start(key: List.filled(32, 2)),
        ];
        await s.db.execute('UPDATE users SET disabled = 1');
        s.clock.advance(const Duration(seconds: 30)); // past the acct: delay
        answers.add(await start());
        await s.db.execute(
          'UPDATE users SET disabled = 0, recovery_auth_hash = NULL',
        );
        s.clock.advance(const Duration(seconds: 30));
        answers.add(await start());
        for (final a in answers) {
          expect(a, {
            'error': 'unauthorized',
            'message': 'Unknown email or invalid recovery key.',
          });
        }
      },
    );

    test('recover resets password and recovery key, revokes every device, opens no session', () async {
      final unlocked = await testCrypto.unlockWithRecovery(
        owner.bundle,
        owner.recoveryKey!,
      );
      final changed = await testCrypto.changePassword(
        unlocked,
        owner.bundle,
        'fresh password',
      );
      final rotated = await testCrypto.rotateRecoveryKey(
        unlocked,
        changed.bundle,
      );
      final r = await s.post(
        '/api/v1/account/recover',
        body: {
          'email': owner.email,
          'recoveryAuthKey': b64(
            await recoveryAuthKey(RecoveryKey.decode(owner.recoveryKey!)),
          ),
          'bundle': rotated.bundle.toJson(),
          'bundleVersion': 0,
          'authKey': b64(changed.authKey),
          'newRecoveryAuthKey': b64(rotated.recoveryAuthKey),
        },
      );
      expect((r.status, r.json), (204, null));
      final row = await userRow();
      expect(row['bundle_version'], 1);
      expect(
        await verifySecret(
          row['recovery_auth_hash'] as String,
          rotated.recoveryAuthKey,
        ),
        isTrue,
      );
      for (final t in [owner.accessToken, other.accessToken]) {
        expect(
          (await s.get('/api/v1/devices', token: t)).body['reason'],
          'device_revoked',
        );
      }
      expect(
        (await start()).containsKey('error'),
        isTrue,
        reason: 'the old recovery key is dead',
      );
      s.clock.advance(const Duration(seconds: 30)); // past the acct: delay
      expect(
        (await s.login(owner.email, 'fresh password')).userId,
        owner.userId,
      );
    });

    test(
      'recover refuses a bundle that changes the key pair, and a stale version',
      () async {
        final key = b64(
          await recoveryAuthKey(RecoveryKey.decode(owner.recoveryKey!)),
        );
        final b = owner.bundle.toJson();
        Future<int> send(Map<String, Object?> bundle, int version) async =>
            (await s.post(
              '/api/v1/account/recover',
              body: {
                'email': owner.email,
                'recoveryAuthKey': key,
                'bundle': bundle,
                'bundleVersion': version,
                'authKey': b64(List.filled(32, 1)),
                'newRecoveryAuthKey': b64(List.filled(32, 2)),
              },
            )).status;
        expect(
          await send({...b, 'publicKey': b64(List.filled(32, 5))}, 0),
          400,
        );
        s.clock.advance(const Duration(seconds: 30)); // past the acct: delay
        expect(await send(b, 3), 409);
        expect((await userRow())['bundle_version'], 0);
      },
    );

    test('recovery-kit replaces only the recovery wrap and proof; needs the current authKey', () async {
      final rotated = await testCrypto.rotateRecoveryKey(
        owner.account,
        owner.bundle,
      );
      Future<TestResponse> send(
        List<int> current, {
        Map<String, Object?>? bundle,
      }) => s.post(
        '/api/v1/account/recovery-kit',
        token: owner.accessToken,
        body: {
          'currentAuthKey': b64(current),
          'bundle': bundle ?? rotated.bundle.toJson(),
          'bundleVersion': 0,
          'recoveryAuthKey': b64(rotated.recoveryAuthKey),
        },
      );
      expect((await send(List.filled(32, 3))).status, 403);
      s.clock.advance(const Duration(seconds: 30)); // past the acct: delay
      final current = await authKeyOf(testPassword, owner.bundle);
      final salted = {
        ...rotated.bundle.toJson(),
        'salt': b64(List.filled(16, 1)),
      };
      expect((await send(current, bundle: salted)).status, 400);
      s.clock.advance(const Duration(seconds: 30));
      expect((await send(current)).status, 204);
      expect(
        await verifySecret(
          (await userRow())['recovery_auth_hash'] as String,
          rotated.recoveryAuthKey,
        ),
        isTrue,
      );
      expect(
        (await s.get('/api/v1/devices', token: other.accessToken)).status,
        200,
        reason: 'no device revoked',
      );
    });

    test(
      'recovery_kit off: recover routes 404 first, recovery-kit after auth',
      () async {
        final off = await TestServer.start(
          env: {'UNFEUDAL_FEATURE_RECOVERY_KIT': 'false'},
        );
        addTearDown(off.close);
        final o = await off.setupOwner();
        expect(
          (await off.post('/api/v1/account/recover/start', body: {})).error,
          'feature_disabled',
        );
        expect(
          (await off.post('/api/v1/account/recover', body: {})).error,
          'feature_disabled',
        );
        expect(
          (await off.post('/api/v1/account/recovery-kit', body: {})).status,
          401,
        );
        expect(
          (await off.post(
            '/api/v1/account/recovery-kit',
            token: o.accessToken,
            body: {},
          )).error,
          'feature_disabled',
        );
      },
    );
  });
}
