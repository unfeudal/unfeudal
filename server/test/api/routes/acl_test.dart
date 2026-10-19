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
        'kim': 'member',
        'dis': 'member',
      },
      teams: {
        'Ops': ['mia', 'max'],
      },
      folders: {'prod': null, 'db': 'prod', 'gone': null},
    );
    await w.acl('prod', 'user:max', allow: ['manage', 'connect', 'edit']);
    await w.keys('prod', 1, ['olivia', 'max']);
    await s.db.execute('UPDATE users SET disabled = 1 WHERE id = @u', {
      'u': w.id('dis'),
    });
    await s.db.execute('UPDATE items SET purged = 1 WHERE id = @f', {
      'f': w.folder('gone'),
    });
  });
  tearDown(() => s.close());

  Map<String, Object?> user(
    String name, {
    List<String> allow = const [],
    List<String> deny = const [],
  }) => {
    'principalType': 'user',
    'principalId': w.id(name),
    'allow': allow,
    'deny': deny,
  };
  Map<String, Object?> team(
    String name, {
    List<String> allow = const [],
    List<String> deny = const [],
  }) => {
    'principalType': 'team',
    'principalId': w.teams[name],
    'allow': allow,
    'deny': deny,
  };
  Future<TestResponse> put(
    String who,
    String folder,
    Object? entries, {
    TestServer? on,
    OrgWorld? world,
  }) => (on ?? s).put(
    '/api/v1/folders/${(world ?? w).folders[folder] ?? folder}/acl',
    token: (world ?? w)[who].accessToken,
    body: {'entries': entries},
  );

  test('admin replaces every entry; org_seq + 1; whoever lost connect gets an acl_change rotation', () async {
    final seq = await w.orgSeq();
    expect(
      (await put('adam', 'prod', [
        team('Ops', allow: ['view']),
        user('max', allow: ['view']),
      ])).status,
      204,
    );
    final rows = await s.db.query(
      'SELECT principal_type, allow FROM acl_entries WHERE folder_id = @f',
      {'f': w.folder('prod')},
    );
    expect(
      rows
          .map(
            (r) => (
              r['principal_type'],
              (jsonDecode(r['allow']! as String) as List).join(','),
            ),
          )
          .toSet(),
      {('team', 'view'), ('user', 'view')},
    );
    expect(await w.orgSeq(), seq + 1);
    final row = (await s.db.query(
      'SELECT reason, removed_user_ids FROM pending_rotations',
    )).single;
    expect(row['reason'], 'acl_change');
    expect(jsonDecode(row['removed_user_ids']! as String), [w.id('max')]);
  });

  test('validation in order: list, folder, membership, manage, entries, principals', () async {
    expect((await put('adam', 'prod', 'x')).status, 400);
    expect((await put('adam', 'prod', [7])).status, 400);
    expect((await put('adam', 'gone', [])).status, 404);
    expect((await put('adam', newId(), [])).status, 404);
    expect(
      (await s.put(
        '/api/v1/folders/${w.folder('prod')}/acl',
        token: w.io.accessToken,
        body: {'entries': <Object?>[]},
      )).status,
      404,
    );
    expect((await put('kim', 'prod', [])).status, 403);
    for (final bad in [
      [
        {...user('kim'), 'principalType': 'role'},
      ],
      [
        user('kim', allow: ['fly']),
      ],
      [
        team('Ops', deny: ['view']),
      ],
      [
        user('kim', allow: ['view']),
        user('kim', allow: ['edit']),
      ],
      [
        user('dis', allow: ['view']),
      ],
      [
        {...user('kim'), 'principalId': w.io.userId},
      ],
      [
        {...team('Ops'), 'principalId': newId()},
      ],
      List.generate(201, (_) => user('kim', allow: ['view'])),
    ]) {
      expect((await put('adam', 'prod', bad)).status, 400, reason: '$bad');
    }
  });

  test('a manage holder cannot grant what they do not hold, on the folder or below', () async {
    expect(
      (await put('max', 'prod', [
        user('max', allow: ['manage', 'connect', 'edit']),
        user('kim', allow: ['reveal']),
      ])).status,
      403,
    );
    expect(
      (await put('max', 'db', [
        user('kim', allow: ['reveal']),
      ])).status,
      403,
    );
    expect(
      (await put('max', 'prod', [
        user('max', allow: ['manage', 'connect', 'edit']),
        user('kim', allow: ['connect']),
      ])).status,
      204,
    );
    expect(
      (await put('max', 'db', [
        user('kim', allow: ['edit']),
      ])).status,
      204,
    );
  });

  test(
    'a non-admin cannot remove their own manage; an admin can do anything',
    () async {
      expect(
        (await put('max', 'prod', [
          user('max', allow: ['view']),
        ])).status,
        400,
      );
      expect(
        (await put('adam', 'prod', [
          user('kim', allow: ['reveal', 'manage']),
        ])).status,
        204,
      );
    },
  );

  test('a trashed folder keeps an editable ACL', () async {
    await s.db.execute('UPDATE items SET deleted = 1 WHERE id = @f', {
      'f': w.folder('prod'),
    });
    expect(
      (await put('adam', 'prod', [
        user('kim', allow: ['view']),
      ])).status,
      204,
    );
  });

  test(
    'user_overrides off refuses user entries; teams off refuses team entries',
    () async {
      final off = await TestServer.start(
        env: {
          'UNFEUDAL_FEATURE_USER_OVERRIDES': 'false',
          'UNFEUDAL_FEATURE_TEAMS': 'false',
        },
      );
      addTearDown(off.close);
      final o = await OrgWorld.build(
        off,
        roles: {'kim': 'member'},
        teams: {
          'Ops': ['kim'],
        },
        folders: {'prod': null},
      );
      expect(
        (await put(
          'olivia',
          'prod',
          [
            {
              'principalType': 'user',
              'principalId': o.id('kim'),
              'allow': ['view'],
              'deny': <String>[],
            },
          ],
          on: off,
          world: o,
        )).status,
        400,
      );
      expect(
        (await put(
          'olivia',
          'prod',
          [
            {
              'principalType': 'team',
              'principalId': o.teams['Ops'],
              'allow': ['view'],
              'deny': <String>[],
            },
          ],
          on: off,
          world: o,
        )).status,
        400,
      );
      expect((await put('olivia', 'prod', [], on: off, world: o)).status, 204);
    },
  );
}
