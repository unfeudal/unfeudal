// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/org_world.dart';
import '../support/test_server.dart';

void main() {
  test(
    'orgs off: every org route is 404 feature_disabled after the token check',
    () async {
      final s = await TestServer.start(env: {'UNFEUDAL_FEATURE_ORGS': 'false'});
      addTearDown(s.close);
      final w = await OrgWorld.build(
        s,
        roles: {'mia': 'member'},
        teams: {
          'Ops': ['mia'],
        },
      );
      final o = w.orgId, f = newId(), t = w.teams['Ops'], u = w.id('mia');
      final token = w['olivia'].accessToken;
      for (final (method, path) in [
        ('POST', '/orgs'),
        ('PUT', '/orgs/$o'),
        ('DELETE', '/orgs/$o'),
        ('PUT', '/orgs/$o/members/$u'),
        ('DELETE', '/orgs/$o/members/$u'),
        ('POST', '/orgs/$o/members/$u/confirm'),
        ('POST', '/orgs/$o/invites'),
        ('GET', '/orgs/$o/invites'),
        ('POST', '/orgs/$o/teams'),
        ('PUT', '/orgs/$o/teams/$t'),
        ('DELETE', '/orgs/$o/teams/$t'),
        ('PUT', '/folders/$f/acl'),
        ('PUT', '/folders/$f/keys'),
        ('POST', '/folders/$f/rotation/done'),
      ]) {
        final r = await s.send(
          method,
          '/api/v1$path',
          token: token,
          body: <String, Object?>{},
        );
        expect(
          (r.status, r.error),
          (404, 'feature_disabled'),
          reason: '$method $path',
        );
        expect(
          (await s.send(
            method,
            '/api/v1$path',
            body: <String, Object?>{},
          )).status,
          401,
          reason: 'token first',
        );
      }
      final info = await s.get('/api/info', token: token);
      expect(info.body['capabilities'], isNot(contains('orgs')));
    },
  );
}
