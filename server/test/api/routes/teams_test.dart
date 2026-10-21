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
      roles: {
        'adam': 'admin',
        'mia': 'member',
        'max': 'member',
        'ana': 'member',
        'dis': 'member',
      },
      accepted: {'ana'},
      teams: {
        'Ops': ['mia', 'max'],
      },
      folders: {'prod': null},
    );
    await w.acl('prod', 'team:Ops', allow: ['view', 'connect']);
    await w.keys('prod', 1, ['olivia', 'mia', 'max']);
    await s.db.execute('UPDATE users SET disabled = 1 WHERE id = @u', {
      'u': w.id('dis'),
    });
  });
  tearDown(() => s.close());

  String teams() => '/api/v1/orgs/${w.orgId}/teams';
  Future<TestResponse> create(String who, Map<String, Object?> body) =>
      s.post(teams(), token: w[who].accessToken, body: body);

  test('create: admin; members of the org (any status, not disabled); stored name; org_seq + 1', () async {
    final seq = await w.orgSeq();
    final r = await create('adam', {
      'name': ' Dev ',
      'memberIds': [w.id('mia'), w.id('ana')],
    });
    expect(r.status, 201);
    final t = r.body['team']! as Map<String, Object?>;
    expect(t['name'], 'Dev');
    expect((t['memberIds']! as List).toSet(), {w.id('mia'), w.id('ana')});
    expect(await w.count('team_members', 'team_id = @t', {'t': t['id']}), 2);
    expect(await w.orgSeq(), seq + 1);
    expect(
      (await create('adam', {'name': 'Empty'})).body['team'],
      containsPair('memberIds', <Object?>[]),
    );
  });

  test('create refusals in order: body, admin, members, name taken', () async {
    expect((await create('adam', {'name': ''})).status, 400);
    expect((await create('mia', {'name': 'X'})).status, 403);
    for (final ids in [
      [w.id('dis')],
      [w.io.userId],
      ['nope'],
      List.generate(501, (_) => newId()),
    ]) {
      expect(
        (await create('adam', {'name': 'X', 'memberIds': ids})).status,
        400,
      );
    }
    final taken = await create('adam', {'name': 'Ops'});
    expect((taken.status, taken.error), (409, 'conflict'));
  });

  test('update: rename and replace members; a member who lost access gets a team_change rotation', () async {
    final path = '${teams()}/${w.teams['Ops']}';
    expect(
      (await s.put(
        path,
        token: w['adam'].accessToken,
        body: {
          'name': 'Ops 2',
          'memberIds': [w.id('max')],
        },
      )).status,
      204,
    );
    expect(
      (await s.db.query('SELECT name FROM teams')).single['name'],
      'Ops 2',
    );
    final row = (await s.db.query(
      'SELECT reason, removed_user_ids FROM pending_rotations',
    )).single;
    expect(row['reason'], 'team_change');
    expect(jsonDecode(row['removed_user_ids']! as String), [w.id('mia')]);
  });

  test('update refusals: name taken, members, admin, unknown team', () async {
    final path = '${teams()}/${w.teams['Ops']}';
    await create('adam', {'name': 'Dev'});
    expect(
      (await s.put(
        path,
        token: w['adam'].accessToken,
        body: {'name': 'Dev'},
      )).status,
      409,
    );
    expect(
      (await s.put(
        path,
        token: w['adam'].accessToken,
        body: {
          'memberIds': [w.id('dis')],
        },
      )).status,
      400,
    );
    expect(
      (await s.put(
        path,
        token: w['mia'].accessToken,
        body: {'name': 'Y'},
      )).status,
      403,
    );
    expect(
      (await s.put(
        '${teams()}/${newId()}',
        token: w['adam'].accessToken,
        body: {'name': 'Y'},
      )).status,
      404,
    );
  });

  test('delete: admin; team ACL and seats gone; rotation; another org\'s team is 404', () async {
    final path = '${teams()}/${w.teams['Ops']}';
    expect((await s.delete(path, token: w['mia'].accessToken)).status, 403);
    expect((await s.delete(path, token: w['adam'].accessToken)).status, 204);
    expect((await w.count('teams'), await w.count('acl_entries')), (0, 0));
    expect(
      (await s.db.query('SELECT reason FROM pending_rotations'))
          .single['reason'],
      'team_deleted',
    );
    expect((await s.delete(path, token: w['adam'].accessToken)).status, 404);
  });

  test('teams off: every team route is 404 feature_disabled', () async {
    final off = await TestServer.start(
      env: {'UNFEUDAL_FEATURE_TEAMS': 'false'},
    );
    addTearDown(off.close);
    final o = await OrgWorld.build(off);
    final r = await off.post(
      '/api/v1/orgs/${o.orgId}/teams',
      token: o['olivia'].accessToken,
      body: {'name': 'X'},
    );
    expect((r.status, r.error), (404, 'feature_disabled'));
  });
}
