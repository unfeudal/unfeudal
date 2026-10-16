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

  test('rotates: a fresh access token and the successor', () async {
    s.clock.advance(const Duration(minutes: 20));
    expect(
      (await s.get('/api/v1/devices', token: owner.accessToken)).status,
      401,
    );
    final r = await s.post(
      '/api/v1/token/refresh',
      body: {'refreshToken': owner.refreshToken},
    );
    expect(r.status, 200);
    final pair = TokenPair.fromJson(r.json);
    expect(r.body.keys, ['accessToken', 'refreshToken']);
    expect(
      (await s.get('/api/v1/devices', token: pair.accessToken)).status,
      200,
    );
  });

  test('replayed refresh token revokes the device for good', () async {
    final first = TokenPair.fromJson(
      (await s.post(
        '/api/v1/token/refresh',
        body: {'refreshToken': owner.refreshToken},
      )).json,
    );
    s.clock.advance(const Duration(minutes: 1));
    final replay = await s.post(
      '/api/v1/token/refresh',
      body: {'refreshToken': owner.refreshToken},
    );
    expect((replay.status, replay.body['reason']), (401, 'device_revoked'));
    expect(
      (await s.get('/api/v1/devices', token: first.accessToken)).body['reason'],
      'device_revoked',
    );
    expect(
      (await s.post(
        '/api/v1/token/refresh',
        body: {'refreshToken': first.refreshToken},
      )).body['reason'],
      'device_revoked',
    );
  });

  test('malformed body is 400; unknown token is 401 invalid_token', () async {
    for (final b in <Object?>[
      {},
      {'refreshToken': 3},
      {'refreshToken': 'x' * 201},
      {'refreshToken': ''},
    ]) {
      expect(
        (await s.post('/api/v1/token/refresh', body: b)).status,
        400,
        reason: '$b',
      );
    }
    final r = await s.post(
      '/api/v1/token/refresh',
      body: {'refreshToken': 'nope'},
    );
    expect((r.status, r.body['reason']), (401, 'invalid_token'));
  });
}
