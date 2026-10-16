// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/version.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../support/test_server.dart';

const u = '5d1e9a7c-2b3f-4c8d-9e0a-1b2c3d4e5f60';
const d = '8c7b6a59-4e3d-4c2b-a190-8f7e6d5c4b3a';

void main() {
  late TestServer s;
  setUp(
    () async => s = await TestServer.start(
      env: {
        'UNFEUDAL_FEATURE_MASCOT': 'false',
        'UNFEUDAL_TRASH_RETENTION_DAYS': '14',
      },
    ),
  );
  tearDown(() => s.close());

  test('healthz: 200 ok; 503 unavailable when the database fails', () async {
    final ok = await s.get('/healthz');
    expect(ok.status, 200);
    expect(ok.json, {'status': 'ok'});
    await s.db.close();
    final down = await s.get('/healthz');
    expect(down.status, 503);
    expect(down.json, {'status': 'unavailable'});
  });

  test(
    'api/info public form for anyone; an invalid token is ignored',
    () async {
      for (final token in [null, 'garbage', 'a.b']) {
        final r = await s.get('/api/info', token: token);
        expect(r.status, 200);
        expect(r.json, {
          'api': [1],
          'minClient': '0.1.0',
          'latestClient': latestClientVersion,
          'capabilities': ['recovery_kit', 'sync'],
        });
        ApiInfo.fromJson(r.json);
      }
    },
  );

  test(
    'api/info full form with a valid access token (MAC and expiry only)',
    () async {
      final r = await s.get(
        '/api/info',
        token: s.deps.access.issue(u, d),
      ); // no such device: still full, nothing secret
      final info = ApiInfo.fromJson(r.json);
      expect(
        (info.server, info.instanceEpoch, info.source, info.trashDays),
        (
          serverVersion,
          s.deps.instanceEpoch,
          'https://github.com/unfeudal/unfeudal',
          14,
        ),
      );
      expect(info.capabilities, [...info.capabilities]..sort());
      expect(
        info.capabilities,
        containsAll(['sync', 'orgs', 'audit', 'recovery_kit']),
      );
      expect(info.capabilities, isNot(contains('mascot')));
      expect(
        info.capabilities,
        isNot(contains('plain_http_lan')),
        reason: 'off by default',
      );
    },
  );
}
