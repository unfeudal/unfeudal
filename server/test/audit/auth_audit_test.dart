// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/audit.dart';
import '../support/test_server.dart';

void main() {
  late TestServer s;
  setUp(() async => s = await TestServer.start());
  tearDown(() => s.close());

  Future<List<int>> authKeyOf(String password, AccountBundle b) async =>
      (await deriveMasterKeys(password, b.salt, b.kdf)).authKey;

  test('setup: setup.completed (instance) then device.added (user); actor = new owner and device', () async {
    final o = await s.setupOwner();
    expect(await actions(s, 'instance'), [
      ['setup.completed', o.userId],
    ]);
    expect(await actions(s, 'user:${o.userId}'), [
      ['device.added', o.deviceId],
    ]);
    final e = (await auditEvents(s, 'instance')).single;
    expect(
      [e.actorUser, e.actorDevice, e.ip, e.ipAddress],
      [
        o.userId,
        o.deviceId,
        await s.deps.audit.ipPseudonym('203.0.113.7'),
        '203.0.113.7',
      ],
    );
  });

  test('login: device.added; wrong key on an account: auth.login_failed without actor; unknown email: nothing', () async {
    final o = await s.setupOwner();
    final again = await s.login(o.email, testPassword);
    final wrong = {
      'email': o.email,
      'authKey': b64(List.filled(32, 1)),
      'device': testDevice(),
    };
    expect((await s.post('/api/v1/login', body: wrong)).status, 401);
    expect(
      (await s.post(
        '/api/v1/login',
        body: {...wrong, 'email': 'nobody@example.org'},
      )).status,
      401,
    );
    final events = await auditEvents(s, 'user:${o.userId}');
    expect(
      [
        for (final e in events) [e.action, ...e.targetIds],
      ],
      [
        ['device.added', o.deviceId],
        ['device.added', again.deviceId],
        ['auth.login_failed'],
      ],
    );
    expect([events.last.actorUser, events.last.actorDevice], [null, null]);
    expect(
      (await s.db.query('SELECT count(*) AS n FROM audit_events')).single['n'],
      4,
      reason: 'setup.completed + 3',
    );
  });

  test('refresh replay: auth.refresh_replay [deviceId], committed with the revocation', () async {
    final o = await s.setupOwner();
    expect(
      (await s.post(
        '/api/v1/token/refresh',
        body: {'refreshToken': o.refreshToken},
      )).status,
      200,
    );
    s.clock.advance(const Duration(seconds: 31));
    expect(
      (await s.post(
        '/api/v1/token/refresh',
        body: {'refreshToken': o.refreshToken},
      )).status,
      401,
    );
    expect((await actions(s, 'user:${o.userId}')).last, [
      'auth.refresh_replay',
      o.deviceId,
    ]);
  });

  test(
    'device revoked, password changed, recovery kit changed, recovery used',
    () async {
      final o = await s.setupOwner();
      final other = await s.login(o.email, testPassword, deviceName: 'Other');
      expect(
        (await s.delete(
          '/api/v1/devices/${other.deviceId}',
          token: o.accessToken,
        )).status,
        204,
      );
      final pw = await testCrypto.changePassword(
        o.account,
        o.bundle,
        'new password!',
      );
      expect(
        (await s.post(
          '/api/v1/account/password',
          token: o.accessToken,
          body: {
            'currentAuthKey': b64(await authKeyOf(testPassword, o.bundle)),
            'bundle': pw.bundle.toJson(),
            'bundleVersion': 0,
            'authKey': b64(pw.authKey),
          },
        )).status,
        204,
      );
      final kit = await testCrypto.rotateRecoveryKey(o.account, pw.bundle);
      expect(
        (await s.post(
          '/api/v1/account/recovery-kit',
          token: o.accessToken,
          body: {
            'currentAuthKey': b64(await authKeyOf('new password!', pw.bundle)),
            'bundle': kit.bundle.toJson(),
            'bundleVersion': 1,
            'recoveryAuthKey': b64(kit.recoveryAuthKey),
          },
        )).status,
        204,
      );
      final unlocked = await testCrypto.unlockWithRecovery(
        kit.bundle,
        kit.recoveryKey,
      );
      final fresh = await testCrypto.changePassword(
        unlocked,
        kit.bundle,
        'fresh password',
      );
      final rotated = await testCrypto.rotateRecoveryKey(
        unlocked,
        fresh.bundle,
      );
      expect(
        (await s.post(
          '/api/v1/account/recover',
          body: {
            'email': o.email,
            'recoveryAuthKey': b64(kit.recoveryAuthKey),
            'bundle': rotated.bundle.toJson(),
            'bundleVersion': 2,
            'authKey': b64(fresh.authKey),
            'newRecoveryAuthKey': b64(rotated.recoveryAuthKey),
          },
        )).status,
        204,
      );
      final events = await auditEvents(s, 'user:${o.userId}');
      expect(
        [
          for (final e in events.skip(2)) [e.action, ...e.targetIds],
        ],
        [
          ['device.revoked', other.deviceId],
          ['account.password_changed'],
          ['account.recovery_kit_changed'],
          ['account.recovery_used'],
        ],
      );
      expect(
        [events[2].actorDevice, events.last.actorUser, events.last.actorDevice],
        [o.deviceId, o.userId, null],
      );
    },
  );
}
