// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/auth/tokens.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../support/test_server.dart';

void main() {
  late TestServer s;
  late TestSession owner;
  setUp(() async {
    s = await TestServer.start(env: {'UNFEUDAL_MAX_DEVICES_PER_USER': '3'});
    owner = await s.setupOwner();
  });
  tearDown(() => s.close());

  Future<TestResponse> loginWith(
    List<int> authKey, {
    String email = 'owner@example.org',
    String ip = '203.0.113.7',
  }) => s.post(
    '/api/v1/login',
    body: {'email': email, 'authKey': b64(authKey), 'device': testDevice()},
    ip: ip,
  );

  test('prelogin returns the real salt and KDF of the stored bundle', () async {
    final r = await s.post(
      '/api/v1/prelogin',
      body: {'email': ' OWNER@example.org'},
    );
    expect(r.json, {
      'salt': b64(owner.bundle.salt),
      'kdf': owner.bundle.kdf.toJson(),
    });
  });

  test(
    'prelogin gives an unknown email a stable fake salt shaped like a real one',
    () async {
      final a = await s.post(
        '/api/v1/prelogin',
        body: {'email': 'ghost@example.org'},
      );
      final b = await s.post(
        '/api/v1/prelogin',
        body: {'email': 'ghost@example.org'},
      );
      expect(a.json, b.json);
      expect(a.body.keys, ['salt', 'kdf']);
      expect(
        a.body['salt'],
        b64(preloginFakeSalt(s.deps.serverSecret, 'ghost@example.org')),
      );
      expect(a.body['kdf'], KdfParams.defaults.toJson());
      await s.db.execute('UPDATE users SET disabled = 1');
      expect(
        (await s.post(
          '/api/v1/prelogin',
          body: {'email': 'owner@example.org'},
        )).body['salt'],
        b64(owner.bundle.salt),
      );
      expect(
        (await s.post('/api/v1/prelogin', body: {'email': 'nope'})).status,
        400,
      );
    },
  );

  test(
    'login opens a session on a new device, resets acct, keeps ip counted',
    () async {
      final second = await s.login(
        'owner@example.org',
        testPassword,
        deviceName: 'Desk',
        ip: '198.51.100.20',
      );
      expect(
        (second.userId, second.deviceId == owner.deviceId),
        (owner.userId, false),
      );
      expect(
        (await s.db.query('SELECT count(*) AS n FROM devices')).single['n'],
        2,
      );
      expect(
        await s.db.query(
          "SELECT key FROM login_attempts WHERE key LIKE 'acct:%'",
        ),
        isEmpty,
      );
      expect(
        (await s.db.query(
          "SELECT count FROM login_attempts WHERE key = 'ip:198.51.100.20'",
        )).single['count'],
        1,
        reason: 'a success on one account does not hide failures on others',
      );
    },
  );

  test('login answers unknown, wrong and disabled the same way', () async {
    final right = await deriveMasterKeys(
      testPassword,
      owner.bundle.salt,
      owner.bundle.kdf,
    );
    final answers = [await loginWith(List.filled(32, 1))];
    s.logLines.clear();
    answers.add(await loginWith(right.authKey, email: 'ghost@example.org'));
    expect(
      s.logLines.where((l) => l.contains('unknown account')),
      hasLength(1),
      reason: 'an unknown email is logged, never audited',
    );
    expect(s.logLines.join(), isNot(contains('ghost')));
    await s.db.execute('UPDATE users SET disabled = 1');
    // Past the acct: delay.
    s.clock.advance(const Duration(seconds: 30));
    answers.add(await loginWith(right.authKey));
    for (final r in answers) {
      expect(r.status, 401);
      expect(r.json, {
        'error': 'unauthorized',
        'message': 'Wrong email or master password.',
      });
    }
  });

  test('after a failure the account refuses attempts for 1 s, then 2 s, even with the right key and from another network', () async {
    final right = await deriveMasterKeys(
      testPassword,
      owner.bundle.salt,
      owner.bundle.kdf,
    );
    expect((await loginWith(List.filled(32, 1))).status, 401);
    final barred = await loginWith(right.authKey, ip: '203.0.113.60');
    expect(
      (barred.status, barred.error, barred.headers['retry-after']),
      (429, 'rate_limited', '1'),
    );
    s.clock.advance(const Duration(seconds: 1));
    expect((await loginWith(List.filled(32, 1))).status, 401);
    expect((await loginWith(right.authKey)).headers['retry-after'], '2');
    s.clock.advance(const Duration(seconds: 2));
    expect((await loginWith(right.authKey)).status, 200);
  });

  test('a locked network is refused even with the right key; another network is not', () async {
    for (var i = 0; i < 10; i++) {
      await loginWith(
        List.filled(32, 1),
        email: 'u$i@example.org',
        ip: '198.51.100.9',
      );
    }
    final right = await deriveMasterKeys(
      testPassword,
      owner.bundle.salt,
      owner.bundle.kdf,
    );
    final locked = await loginWith(right.authKey, ip: '198.51.100.9');
    expect((locked.status, locked.error), (429, 'rate_limited'));
    expect((await loginWith(right.authKey, ip: '203.0.113.50')).status, 200);
  });

  test(
    'the attempt is counted even when the rest of the body is malformed',
    () async {
      final r = await s.post(
        '/api/v1/login',
        body: {'email': 'owner@example.org', 'authKey': 'short'},
        ip: '198.51.100.30',
      );
      expect(r.status, 400);
      expect(
        (await s.db.query(
          "SELECT count FROM login_attempts WHERE key = 'ip:198.51.100.30'",
        )).single['count'],
        1,
      );
      expect(
        (await s.post('/api/v1/login', body: {'email': 'bad'})).status,
        400,
      );
    },
  );

  // The owner holds the three devices of the cap afterwards.
  Future<void> fillDeviceCap() async {
    for (var i = 0; i < 2; i++) {
      await s.login('owner@example.org', testPassword);
    }
  }

  Future<List<int>> rightAuthKey() async => (await deriveMasterKeys(
    testPassword,
    owner.bundle.salt,
    owner.bundle.kdf,
  )).authKey;

  test('device cap: active devices >= max_devices_per_user is 403', () async {
    await fillDeviceCap();
    expect((await loginWith(await rightAuthKey())).status, 403);
  });

  test('device cap: the right key is not counted as a failure', () async {
    await fillDeviceCap();
    await loginWith(await rightAuthKey());
    expect(
      await s.db.query(
        "SELECT key FROM login_attempts WHERE key LIKE 'acct:%'",
      ),
      isEmpty,
    );
  });

  test('device cap: revoked devices do not count', () async {
    await fillDeviceCap();
    await s.db.execute("UPDATE devices SET revoked_at = @t WHERE id = @d", {
      't': iso(s.clock.now()),
      'd': owner.deviceId,
    });
    expect((await loginWith(await rightAuthKey())).status, 200);
  });
}
