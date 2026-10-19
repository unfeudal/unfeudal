// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:test/test.dart';

import '../../support/org_world.dart';
import '../../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  setUp(() async {
    s = await TestServer.start();
    w = await OrgWorld.build(
      s,
      roles: {
        'oscar': 'owner',
        'adam': 'admin',
        'ada': 'admin',
        'mia': 'member',
        'ana': 'member',
      },
      accepted: {'ana'},
      folders: {'prod': null},
    );
    await w.acl('prod', 'user:mia', allow: ['view']);
    await w.keys('prod', 1, ['olivia', 'adam', 'mia']);
  });
  tearDown(() => s.close());

  String member(String name) => '/api/v1/orgs/${w.orgId}/members/${w.id(name)}';
  Future<int> role(String who, String target, String newRole) async =>
      (await s.put(
        member(target),
        token: w[who].accessToken,
        body: {'role': newRole},
      )).status;
  Future<String?> roleOf(String name) async =>
      (await s.db.query('SELECT role FROM org_members WHERE user_id = @u', {
            'u': w.id(name),
          })).firstOrNull?['role']
          as String?;

  test('only a confirmed owner touches the admin and owner roles', () async {
    expect(await role('adam', 'mia', 'admin'), 403);
    expect(await role('adam', 'ada', 'member'), 403);
    expect(await role('adam', 'olivia', 'member'), 403);
    expect(await role('adam', 'mia', 'member'), 204);
    expect(await role('olivia', 'mia', 'admin'), 204);
    expect(await roleOf('mia'), 'admin');
    expect(await role('mia', 'ana', 'member'), 204, reason: 'mia is admin now');
  });

  test('role checks in order: role, admin, target, owner rule', () async {
    expect(await role('olivia', 'mia', 'boss'), 400);
    expect(await role('mia', 'ana', 'member'), 403);
    expect(
      (await s.put(
        '/api/v1/orgs/${w.orgId}/members/${w.io.userId}',
        token: w['olivia'].accessToken,
        body: {'role': 'member'},
      )).status,
      404,
    );
    expect(
      (await s.put(
        member('mia'),
        token: w.io.accessToken,
        body: {'role': 'member'},
      )).status,
      404,
    );
  });

  test(
    'the last confirmed enabled owner cannot leave, be demoted or removed',
    () async {
      await s.db.execute('UPDATE users SET disabled = 1 WHERE id = @u', {
        'u': w.id('oscar'),
      });
      final r = await s.put(
        member('olivia'),
        token: w['olivia'].accessToken,
        body: {'role': 'admin'},
      );
      expect(r.status, 409);
      expect(r.body['reason'], 'last_owner');
      expect(r.body['orgs'], ['Acme']);
      expect(
        (await s.delete(
          member('olivia'),
          token: w['olivia'].accessToken,
        )).status,
        409,
      );
      await s.db.execute('UPDATE users SET disabled = 0 WHERE id = @u', {
        'u': w.id('oscar'),
      });
      expect(
        (await s.delete(
          member('olivia'),
          token: w['oscar'].accessToken,
        )).status,
        204,
      );
      expect(
        (await s.delete(member('oscar'), token: w['oscar'].accessToken)).status,
        409,
      );
    },
  );

  test(
    'a demoted admin loses what no ACL gives: rotation recorded, org_seq + 1',
    () async {
      final seq = await w.orgSeq();
      expect(await role('olivia', 'adam', 'member'), 204);
      final row = (await s.db.query(
        'SELECT reason, removed_user_ids FROM pending_rotations',
      )).single;
      expect(row['reason'], 'role_change');
      expect(jsonDecode(row['removed_user_ids']! as String), [w.id('adam')]);
      expect(await w.orgSeq(), seq + 1);
    },
  );

  test(
    'remove: self (any status) or admin; admins and owners need an owner',
    () async {
      expect(
        (await s.delete(member('ana'), token: w['ana'].accessToken)).status,
        204,
        reason: 'unconfirmed leave',
      );
      expect(
        (await s.delete(member('adam'), token: w['mia'].accessToken)).status,
        403,
      );
      expect(
        (await s.delete(member('ada'), token: w['adam'].accessToken)).status,
        403,
      );
      expect(
        (await s.delete(member('mia'), token: w.io.accessToken)).status,
        404,
      );
      expect(
        (await s.delete(
          '/api/v1/orgs/${w.orgId}/members/${w.io.userId}',
          token: w['adam'].accessToken,
        )).status,
        404,
      );
      expect(
        (await s.delete(member('mia'), token: w['adam'].accessToken)).status,
        204,
      );
      final row = (await s.db.query(
        'SELECT reason, removed_user_ids FROM pending_rotations',
      )).single;
      expect(row['reason'], 'member_removed');
      expect(jsonDecode(row['removed_user_ids']! as String), [w.id('mia')]);
      expect(
        (await s.delete(member('adam'), token: w['adam'].accessToken)).status,
        204,
        reason: 'an admin may leave',
      );
      expect(
        (await s.db.query('SELECT reason FROM pending_rotations'))
            .single['reason'],
        'member_left',
      );
      expect(
        (await s.delete(member('ada'), token: w['olivia'].accessToken)).status,
        204,
      );
    },
  );

  test('confirm: admin only, accepted only; org_seq + 1', () async {
    final path = '${member('ana')}/confirm';
    expect((await s.post(path, token: w['mia'].accessToken)).status, 403);
    final seq = await w.orgSeq();
    expect((await s.post(path, token: w['adam'].accessToken)).status, 204);
    expect(
      (await s.db.query('SELECT status FROM org_members WHERE user_id = @u', {
        'u': w.id('ana'),
      })).single['status'],
      'confirmed',
    );
    expect(await w.orgSeq(), seq + 1);
    expect((await s.post(path, token: w['adam'].accessToken)).status, 400);
    expect(
      (await s.post(
        '/api/v1/orgs/${w.orgId}/members/${w.io.userId}/confirm',
        token: w['adam'].accessToken,
      )).status,
      404,
    );
  });
}
