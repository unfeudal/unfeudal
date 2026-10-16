// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../support/test_server.dart';

void main() {
  late TestServer s;
  late TestSession owner;
  setUp(() async {
    s = await TestServer.start();
    owner = await s.setupOwner();
  });
  tearDown(() => s.close());

  test(
    'lists own devices oldest first, revoked included, current marked',
    () async {
      s.clock.advance(const Duration(minutes: 1));
      final second = await s.login(
        owner.email,
        testPassword,
        deviceName: 'Desk',
      );
      final other = await s.createUser('bob@example.org');
      await s.delete(
        '/api/v1/devices/${second.deviceId}',
        token: owner.accessToken,
      );
      final r = await s.get('/api/v1/devices', token: owner.accessToken);
      final devices = [
        for (final d in r.body['devices']! as List) Device.fromJson(d),
      ];
      expect(devices.map((d) => (d.id, d.current, d.revokedAt != null)), [
        (owner.deviceId, true, false),
        (second.deviceId, false, true),
      ]);
      expect(devices.any((d) => d.id == other.deviceId), isFalse);
      expect(devices.first.name, 'Test device');
    },
  );

  test('revoking a device refuses its tokens at once; again is 204', () async {
    final second = await s.login(owner.email, testPassword);
    expect(
      (await s.delete(
        '/api/v1/devices/${second.deviceId}',
        token: owner.accessToken,
      )).status,
      204,
    );
    expect(
      (await s.get(
        '/api/v1/devices',
        token: second.accessToken,
      )).body['reason'],
      'device_revoked',
    );
    expect(
      await s.db.query(
        'SELECT token_hash FROM refresh_tokens WHERE device_id = @d AND used_at IS NULL',
        {'d': second.deviceId},
      ),
      isEmpty,
    );
    expect(
      (await s.delete(
        '/api/v1/devices/${second.deviceId}',
        token: owner.accessToken,
      )).status,
      204,
    );
  });

  test('the current device can be revoked', () async {
    expect(
      (await s.delete(
        '/api/v1/devices/${owner.deviceId}',
        token: owner.accessToken,
      )).status,
      204,
    );
    expect(
      (await s.get('/api/v1/devices', token: owner.accessToken)).status,
      401,
    );
  });

  test('not a UUID is 400; another account\'s device or none is 404', () async {
    final bob = await s.createUser('bob@example.org');
    expect(
      (await s.delete(
        '/api/v1/devices/NOT-A-UUID',
        token: owner.accessToken,
      )).status,
      400,
    );
    expect(
      (await s.delete(
        '/api/v1/devices/${bob.deviceId}',
        token: owner.accessToken,
      )).status,
      404,
    );
    expect(
      (await s.delete(
        '/api/v1/devices/${newId()}',
        token: owner.accessToken,
      )).status,
      404,
    );
    expect(
      (await s.get('/api/v1/devices', token: bob.accessToken)).status,
      200,
    );
  });
}
