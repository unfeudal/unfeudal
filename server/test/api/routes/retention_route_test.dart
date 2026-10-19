// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';

import '../../support/org_world.dart';
import '../../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  setUp(() async {
    s = await TestServer.start();
    w = await OrgWorld.build(s, roles: {'adam': 'admin', 'mia': 'member'});
  });
  tearDown(() => s.close());

  test(
    'admins read server and org values; members 403, strangers 404, bad id 400',
    () async {
      final path = '/api/v1/orgs/${w.orgId}/settings/retention';
      await s.put(
        '/api/v1/orgs/${w.orgId}',
        token: w['olivia'].accessToken,
        body: {
          'settings': {'auditDays': 90, 'trashDays': 7},
        },
      );
      expect((await s.get(path, token: w['adam'].accessToken)).body, {
        'server': {'auditDays': 365, 'maxVersions': 50, 'trashDays': 30},
        'org': {'auditDays': 90, 'maxVersions': null, 'trashDays': 7},
      });
      final zed = await s.createUser('zed@example.org');
      expect(
        [
          (await s.get(path, token: w['mia'].accessToken)).status,
          (await s.get(path, token: zed.accessToken)).status,
          (await s.get(
            '/api/v1/orgs/nope/settings/retention',
            token: w['adam'].accessToken,
          )).status,
        ],
        [403, 404, 400],
      );
    },
  );

  test('orgs off → 404 feature_disabled', () async {
    final off = await TestServer.start(env: {'UNFEUDAL_FEATURE_ORGS': 'false'});
    final o = await off.setupOwner();
    expect(
      (await off.get(
        '/api/v1/orgs/${w.orgId}/settings/retention',
        token: o.accessToken,
      )).error,
      'feature_disabled',
    );
    await off.close();
  });
}
