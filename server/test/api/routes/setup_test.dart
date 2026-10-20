// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/auth/secret_hash.dart';
import 'package:unfeudal_server/src/auth/tokens.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../support/test_server.dart';

void main() {
  late TestServer s;
  late NewAccount acc;
  setUp(() async {
    s = await TestServer.start();
    acc = await testCrypto.create(testPassword);
  });
  tearDown(() => s.close());

  Map<String, Object?> body([Map<String, Object?> over = const {}]) => {
    'token': testSetupToken,
    'email': ' Owner@Example.ORG ',
    'bundle': acc.bundle.toJson(),
    'authKey': b64(acc.authKey),
    'recoveryAuthKey': b64(acc.recoveryAuthKey),
    'device': testDevice('Laptop'),
    'locale': 'fr',
    ...over,
  };

  Future<Session> createOwner() async {
    final r = await s.post(
      '/api/v1/setup',
      body: body({'token': 'abcd efgh-ijkl mnop-qrst uvwx-yz'}),
    );
    expect(r.status, 201);
    return Session.fromJson(r.json);
  }

  test('creates the Instance Owner session with its bundle', () async {
    final session = await createOwner();
    expect((session.isInstanceOwner, session.bundleVersion), (true, 0));
    expect(session.bundle.toJson(), acc.bundle.toJson());
  });

  test('stores the Instance Owner with hashed auth keys', () async {
    final session = await createOwner();
    final user = (await s.db.query('SELECT * FROM users')).single;
    expect(
      (user['id'], user['email'], user['is_instance_owner'], user['locale']),
      (session.userId, 'owner@example.org', 1, 'fr'),
    );
    expect(
      await verifySecret(user['auth_hash'] as String, acc.authKey),
      isTrue,
    );
    expect(
      await verifySecret(
        user['recovery_auth_hash'] as String,
        acc.recoveryAuthKey,
      ),
      isTrue,
    );
  });

  test('registers the first device and consumes the setup token', () async {
    final session = await createOwner();
    final device = (await s.db.query('SELECT id, name, platform FROM devices'))
        .single;
    expect(device, {
      'id': session.deviceId,
      'name': 'Laptop',
      'platform': 'linux',
    });
    expect(
      await s.db.query("SELECT key FROM meta WHERE key = 'setup_token_hash'"),
      isEmpty,
    );
  });

  test('issues the first session tokens for the first device', () async {
    final session = await createOwner();
    expect(
      s.deps.access.verify(session.accessToken)!.deviceId,
      session.deviceId,
    );
    expect(
      (await s.db.query(
        'SELECT device_id FROM refresh_tokens WHERE token_hash = @h',
        {'h': hashToken(session.refreshToken)},
      )).single['device_id'],
      session.deviceId,
    );
  });

  test('the token stops working after setup', () async {
    expect((await s.post('/api/v1/setup', body: body())).status, 201);
    final again = await s.post(
      '/api/v1/setup',
      body: body({'email': 'other@example.org'}),
    );
    expect((again.status, again.error), (409, 'setup_done'));
  });

  test(
    'wrong or missing token is 401 without reason; malformed input is 400',
    () async {
      final wrong = await s.post(
        '/api/v1/setup',
        body: body({'token': 'AAAAAAAAAAAAAAAAAAAAAAAAAA'}),
      );
      expect(
        (wrong.status, wrong.error, wrong.body.containsKey('reason')),
        (401, 'unauthorized', false),
      );
      for (final over in <Map<String, Object?>>[
        {'email': 'nope'},
        {'authKey': 'AAAA'},
        {
          'device': {'name': '', 'platform': 'linux'},
        },
        {'locale': 'de'},
        {'bundle': {}},
        {'token': 'x' * 201},
      ]) {
        expect(
          (await s.post('/api/v1/setup', body: body(over))).status,
          400,
          reason: '$over',
        );
      }
      expect(await s.db.query('SELECT id FROM users'), isEmpty);
    },
  );

  test('locale defaults to en', () async {
    expect(
      (await s.post('/api/v1/setup', body: body()..remove('locale'))).status,
      201,
    );
    expect(
      (await s.db.query('SELECT locale FROM users')).single['locale'],
      'en',
    );
  });

  test('concurrent setups create exactly one Instance Owner', () async {
    final results = await Future.wait([
      for (var i = 0; i < 5; i++)
        s.post(
          '/api/v1/setup',
          body: body({'email': 'o$i@example.org'}),
          ip: '198.51.100.$i',
        ),
    ]);
    expect(results.where((r) => r.status == 201), hasLength(1));
    expect(results.where((r) => r.status != 201).map((r) => r.error).toSet(), {
      'setup_done',
    });
    expect(
      (await s.db.query('SELECT count(*) AS n FROM users')).single['n'],
      1,
    );
  });

  test('every attempt counts toward ip: and is never refunded', () async {
    for (var i = 0; i < 10; i++) {
      await s.post(
        '/api/v1/setup',
        body: body({'token': 'AAAAAAAAAAAAAAAAAAAAAAAAAA'}),
      );
    }
    final locked = await s.post('/api/v1/setup', body: body());
    expect(
      (locked.status, locked.error, locked.headers['retry-after']),
      (429, 'rate_limited', '900'),
    );
  });
}
