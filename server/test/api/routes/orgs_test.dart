// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../support/org_world.dart';
import '../../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  setUp(() async {
    s = await TestServer.start();
    w = await OrgWorld.build(
      s,
      roles: {'adam': 'admin', 'mia': 'member'},
      folders: {'prod': null},
    );
  });
  tearDown(() => s.close());

  Future<Map<String, Object?>> settings(String orgId) async => jsonDecode(
    (await s.db.query('SELECT settings FROM orgs WHERE id = @o', {
          'o': orgId,
        })).single['settings']!
        as String,
  ) as Map<String, Object?>;

  test('create: caller is the confirmed owner, empty settings, org_seq + 1, name trimmed', () async {
    final seq = await w.orgSeq();
    final r = await s.post(
      '/api/v1/orgs',
      token: w['mia'].accessToken,
      body: {'name': '  Beta  '},
    );
    expect(r.status, 201);
    final org = r.body['org']! as Map<String, Object?>;
    expect(
      (org['name'], org['role'], isUuid(org['id']! as String)),
      ('Beta', 'owner', true),
    );
    final m = (await s.db.query(
      'SELECT role, status FROM org_members WHERE org_id = @o',
      {'o': org['id']},
    )).single;
    expect((m['role'], m['status']), ('owner', 'confirmed'));
    expect(await settings(org['id']! as String), isEmpty);
    expect(await w.orgSeq(), seq + 1);
  });

  test(
    'create: names are 1 to 100 code points without control chars',
    () async {
      for (final bad in ['', '   ', 'x' * 101, 'a\u0007b', 7, null]) {
        expect(
          (await s.post(
            '/api/v1/orgs',
            token: w['mia'].accessToken,
            body: {'name': bad},
          )).status,
          400,
          reason: '$bad',
        );
      }
      expect(
        (await s.post(
          '/api/v1/orgs',
          token: w['mia'].accessToken,
          body: {'name': 'é' * 100},
        )).status,
        201,
      );
    },
  );

  test('create: org_creation, max_orgs_per_user, orgs flag', () async {
    final io = await TestServer.start(
      env: {
        'UNFEUDAL_ORG_CREATION': 'instance_owner',
        'UNFEUDAL_MAX_ORGS_PER_USER': '1',
      },
    );
    addTearDown(io.close);
    final owner = await io.setupOwner();
    final bob = await io.createUser('bob@example.org');
    expect(
      (await io.post(
        '/api/v1/orgs',
        token: bob.accessToken,
        body: {'name': 'B'},
      )).status,
      403,
    );
    final r = await io.post(
      '/api/v1/orgs',
      token: owner.accessToken,
      body: {'name': 'A'},
    );
    expect(r.status, 201);
    expect(
      (await io.post(
        '/api/v1/orgs',
        token: owner.accessToken,
        body: {'name': 'C'},
      )).status,
      403,
      reason: 'cap 1',
    );
    final off = await TestServer.start(env: {'UNFEUDAL_FEATURE_ORGS': 'false'});
    addTearDown(off.close);
    final o = await off.setupOwner();
    final r2 = await off.post(
      '/api/v1/orgs',
      token: o.accessToken,
      body: {'name': 'A'},
    );
    expect((r2.status, r2.error), (404, 'feature_disabled'));
    expect((await s.post('/api/v1/orgs', body: {'name': 'A'})).status, 401);
  });

  Future<int> updateAsAdam(Map<String, Object?> body) async => (await s.put(
    '/api/v1/orgs/${w.orgId}',
    token: w['adam'].accessToken,
    body: body,
  )).status;

  test('update: admin only', () async {
    final path = '/api/v1/orgs/${w.orgId}';
    expect(
      (await s.put(path, token: w.io.accessToken, body: {'name': 'X'})).status,
      404,
    );
    expect(
      (await s.put(
        path,
        token: w['mia'].accessToken,
        body: {'name': 'X'},
      )).status,
      403,
    );
  });

  test(
    'update: retention values and an empty body leave org_seq alone',
    () async {
      var seq = await w.orgSeq();
      expect(
        await updateAsAdam({
          'settings': {'auditDays': 90},
        }),
        204,
      );
      expect(await w.orgSeq(), seq, reason: 'retention is not in the block');
      seq = await w.orgSeq();
      expect(await updateAsAdam(<String, Object?>{}), 204);
      expect(await w.orgSeq(), seq);
    },
  );

  test('update: name and mascot bump org_seq; settings are merged', () async {
    await updateAsAdam({
      'settings': {'auditDays': 90},
    });
    final seq = await w.orgSeq();
    expect(
      await updateAsAdam({
        'name': 'Acme 2',
        'settings': {'mascot': false},
      }),
      204,
    );
    expect(await w.orgSeq(), seq + 1);
    expect(await settings(w.orgId), {'auditDays': 90, 'mascot': false});
  });

  test('update: a null retention value clears it', () async {
    await updateAsAdam({
      'settings': {'auditDays': 90, 'mascot': false},
    });
    expect(
      await updateAsAdam({
        'settings': {'auditDays': null},
      }),
      204,
    );
    expect(await settings(w.orgId), {'mascot': false});
  });

  test('update: mascot and retention values are checked', () async {
    final path = '/api/v1/orgs/${w.orgId}';
    for (final bad in <Map<String, Object?>>[
      {'name': ''},
      {'settings': 'x'},
      {
        'settings': {'mascot': 'no'},
      },
      {
        'settings': {'auditDays': 29},
      },
      {
        'settings': {'auditDays': 366},
      },
      {
        'settings': {'maxVersions': 0},
      },
      {
        'settings': {'maxVersions': 51},
      },
      {
        'settings': {'trashDays': 31},
      },
      {
        'settings': {'trashDays': 1.5},
      },
      {
        'settings': {'unknown': 1},
      },
      // Only the retention values clear with null.
      {
        'settings': {'mascot': null},
      },
      {
        'settings': {'mascot': 'yes'},
      },
    ]) {
      expect(
        (await s.put(path, token: w['olivia'].accessToken, body: bad)).status,
        400,
        reason: '$bad',
      );
    }
    for (final ok in [
      {'auditDays': 30},
      {'auditDays': 365},
      {'maxVersions': 1},
      {'trashDays': 30},
    ]) {
      expect(
        (await s.put(
          path,
          token: w['olivia'].accessToken,
          body: {'settings': ok},
        )).status,
        204,
        reason: '$ok',
      );
    }
    final forever = await TestServer.start(
      env: {'UNFEUDAL_AUDIT_RETENTION_DAYS': '0'},
    );
    addTearDown(forever.close);
    final f = await OrgWorld.build(forever);
    final fp = '/api/v1/orgs/${f.orgId}';
    expect(
      (await forever.put(
        fp,
        token: f['olivia'].accessToken,
        body: {
          'settings': {'auditDays': 36500},
        },
      )).status,
      204,
    );
    expect(
      (await forever.put(
        fp,
        token: f['olivia'].accessToken,
        body: {
          'settings': {'auditDays': 36501},
        },
      )).status,
      400,
    );
  });

  test(
    'delete: confirmed owner only; the org and its content are gone',
    () async {
      final path = '/api/v1/orgs/${w.orgId}';
      expect((await s.delete(path, token: w.io.accessToken)).status, 404);
      expect((await s.delete(path, token: w['adam'].accessToken)).status, 403);
      final seq = await w.orgSeq();
      expect(
        (await s.delete(path, token: w['olivia'].accessToken)).status,
        204,
      );
      expect(
        (await w.count('orgs'), await w.count('items', 'org_id IS NOT NULL')),
        (0, 0),
      );
      expect(await w.orgSeq(), seq + 1);
      expect(
        (await s.delete(
          '/api/v1/orgs/not-a-uuid',
          token: w['olivia'].accessToken,
        )).status,
        400,
      );
    },
  );
}
