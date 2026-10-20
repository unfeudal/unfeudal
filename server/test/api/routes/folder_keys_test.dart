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
        'vic': 'member',
        'kim': 'member',
        'dis': 'member',
      },
      folders: {'prod': null, 'gone': null},
    );
    await w.acl('prod', 'user:mia', allow: ['connect', 'edit']);
    await w.acl('prod', 'user:vic', allow: ['view']);
    await w.acl('prod', 'user:dis', allow: ['view']);
    await s.db.execute('UPDATE users SET disabled = 1 WHERE id = @u', {
      'u': w.id('dis'),
    });
    await s.db.execute('UPDATE items SET purged = 1 WHERE id = @f', {
      'f': w.folder('gone'),
    });
  });
  tearDown(() => s.close());

  Future<TestResponse> keys(
    String who,
    String folder,
    int version,
    List<Map<String, Object?>> wrapped, {
    Map<String, Object?>? history,
  }) => s.put(
    '/api/v1/folders/${w.folders[folder] ?? folder}/keys',
    token: w[who].accessToken,
    body: {'version': version, 'wrapped': wrapped, 'history': history},
  );
  Future<List<(Object?, Object?, bool)>> rows(String folder) async => [
    for (final r in await s.db.query(
      'SELECT user_id, version, secret_wrapped FROM folder_keys WHERE folder_id = @f ORDER BY user_id',
      {'f': w.folder(folder)},
    ))
      (r['user_id'], r['version'], r['secret_wrapped'] != null),
  ];
  List<Map<String, Object?>> prodWrapsAt2() => [
    w.wrap('olivia', 'prod', 2),
    w.wrap('adam', 'prod', 2),
    w.wrap('mia', 'prod', 2),
    w.wrap('vic', 'prod', 2, secret: false),
  ];

  test(
    'first upload: the creator with edit, folder at revision 1, version 1 only',
    () async {
      final sub = await w.item(w['mia'], type: 'folder', folder: 'prod');
      expect((await w.put(w['mia'], sub, 0)).status, 200);
      w.folders['sub'] = sub['id']! as String;
      expect(
        (await keys('mia', 'sub', 2, [w.wrap('mia', 'sub', 2)])).status,
        400,
      );
      final seq = await w.orgSeq();
      expect(
        (await keys('mia', 'sub', 1, [w.wrap('mia', 'sub', 1)])).status,
        204,
      );
      expect(await rows('sub'), [(w.id('mia'), 1, true)]);
      expect(await w.orgSeq(), seq + 1);
      expect(
        (await keys('mia', 'sub', 1, [w.wrap('mia', 'sub', 1)])).status,
        403,
        reason: 'current is 1: admins only now',
      );
      expect(
        (await keys('vic', 'prod', 1, [
          w.wrap('vic', 'prod', 1, secret: false),
        ])).status,
        403,
        reason: 'not the creator',
      );
    },
  );

  test('admin handoff at the current version upserts wraps', () async {
    await w.keys('prod', 1, ['olivia']);
    expect(
      (await keys('adam', 'prod', 1, [
        w.wrap('mia', 'prod', 1),
        w.wrap('vic', 'prod', 1, secret: false),
      ])).status,
      204,
    );
    final ids = [w.id('mia'), w.id('olivia'), w.id('vic')]..sort();
    expect((await rows('prod')).map((r) => r.$1), ids);
    expect(
      (await keys('adam', 'prod', 3, [w.wrap('mia', 'prod', 3)])).status,
      400,
      reason: 'neither handoff nor rotation',
    );
  });

  test('a secret wrap for a view-only member is 400; so are readers without view, disabled users and bad labels', () async {
    await w.keys('prod', 1, ['olivia']);
    for (final bad in [
      w.wrap('vic', 'prod', 1),
      w.wrap('kim', 'prod', 1, secret: false),
      w.wrap('dis', 'prod', 1, secret: false),
      {...w.wrap('mia', 'prod', 1), 'version': 2},
      {
        ...w.wrap('mia', 'prod', 1),
        'meta': OrgWorld.sealed(w.folder('gone'), 1, 'meta'),
      },
      {
        ...w.wrap('mia', 'prod', 1),
        'secret': OrgWorld.sealed(w.folder('prod'), 1, 'meta'),
      },
    ]) {
      expect(
        (await keys('adam', 'prod', 1, [bad])).status,
        400,
        reason: '$bad',
      );
    }
    expect(
      (await keys('adam', 'prod', 1, [
        w.wrap('mia', 'prod', 1),
        w.wrap('mia', 'prod', 1),
      ])).status,
      400,
      reason: 'duplicate',
    );
    expect(
      (await keys(
        'adam',
        'prod',
        1,
        List.generate(1001, (_) => w.wrap('mia', 'prod', 1)),
      )).status,
      400,
    );
    expect(
      (await s.put(
        '/api/v1/folders/${w.folder('prod')}/keys',
        token: w['adam'].accessToken,
        body: {'version': '1', 'wrapped': <Object?>[]},
      )).status,
      400,
    );
  });

  test('a malformed body is 400 before any folder lookup', () async {
    Future<Object?> message(Map<String, Object?> body) async => (await s.put(
      '/api/v1/folders/${w.folder('prod')}/keys',
      token: w['adam'].accessToken,
      body: body,
    )).body['message'];
    final noUser = {...w.wrap('mia', 'prod', 1)}..remove('userId');
    expect(await message({'version': 1}), 'version and wrapped are required.');
    expect(
      await message({
        'version': 1,
        'wrapped': [
          {'version': 1},
        ],
      }),
      startsWith('invalid wrap: '),
    );
    expect(
      await message({
        'version': 1,
        'wrapped': [noUser],
      }),
      'one wrap per user, userId required.',
    );
  });

  Future<void> queueKimRemoval() async {
    await w.keys('prod', 1, ['olivia', 'adam', 'mia', 'vic', 'kim']);
    await s.db.execute(
      "INSERT INTO pending_rotations (org_id, folder_id, reason, removed_user_ids) VALUES (@o, @f, 'member_removed', @ids)",
      {
        'o': w.orgId,
        'f': w.folder('prod'),
        'ids': jsonEncode([w.id('kim')]),
      },
    );
  }

  test('a rotation must cover every confirmed enabled reader with the new history, by a manager', () async {
    await queueKimRemoval();
    final all = prodWrapsAt2();
    expect(
      (await keys(
        'adam',
        'prod',
        2,
        all.sublist(1),
        history: w.history('prod', 2),
      )).status,
      400,
      reason: 'olivia missing',
    );
    expect(
      (await keys('adam', 'prod', 2, all)).status,
      400,
      reason: 'no history',
    );
    expect(
      (await keys(
        'adam',
        'prod',
        2,
        all,
        history: w.history('prod', 1),
      )).status,
      400,
      reason: 'history version',
    );
    expect(
      (await keys('mia', 'prod', 2, all, history: w.history('prod', 2))).status,
      403,
    );
  });

  test('a rotation wipes the old wraps and records its version', () async {
    await queueKimRemoval();
    expect(
      (await keys(
        'adam',
        'prod',
        2,
        prodWrapsAt2(),
        history: w.history('prod', 2),
      )).status,
      204,
    );
    expect((await rows('prod')).map((r) => r.$2).toSet(), {2});
    expect(await w.count('folder_keys', 'user_id = @u', {'u': w.id('kim')}), 0);
    expect(
      (await s.db.query('SELECT version FROM folder_key_history'))
          .single['version'],
      2,
    );
    expect(
      (await s.db.query('SELECT rotated_version FROM pending_rotations'))
          .single['rotated_version'],
      2,
    );
  });

  test(
    'folder and caller lookups: purged or unknown 404, outsider 404',
    () async {
      expect((await keys('adam', 'gone', 1, [])).status, 404);
      expect((await keys('adam', newId(), 1, [])).status, 404);
      expect(
        (await s.put(
          '/api/v1/folders/${w.folder('prod')}/keys',
          token: w.io.accessToken,
          body: {'version': 1, 'wrapped': <Object?>[], 'history': null},
        )).status,
        404,
      );
    },
  );

  String rotationDone() => '/api/v1/folders/${w.folder('prod')}/rotation/done';

  test('rotation/done: idempotent without a row, 403 without manage', () async {
    final done = rotationDone();
    expect((await s.post(done, token: w['adam'].accessToken)).status, 204);
    expect((await s.post(done, token: w['mia'].accessToken)).status, 403);
  });

  Future<Map<String, Object?>> queueRotationWithHost() async {
    await w.keys('prod', 1, ['olivia', 'mia']);
    final host = await w.item(w['olivia'], folder: 'prod', secret: true);
    expect((await w.put(w['olivia'], host, 0)).status, 200);
    await s.db.execute(
      "INSERT INTO pending_rotations (org_id, folder_id, reason, removed_user_ids) VALUES (@o, @f, 'acl_change', '[]')",
      {'o': w.orgId, 'f': w.folder('prod')},
    );
    return host;
  }

  Future<TestResponse> rotateProdTo2() =>
      keys('adam', 'prod', 2, prodWrapsAt2(), history: w.history('prod', 2));

  Future<TestResponse> resealProdFolderAt2() async => w.put(
    w['olivia'],
    await w.item(
      w['olivia'],
      id: w.folder('prod'),
      type: 'folder',
      keyVersion: 2,
    ),
    1,
  );

  Future<void> trash(Map<String, Object?> item) => s.db.execute(
    'UPDATE items SET deleted = 1 WHERE id = @i',
    {'i': item['id']},
  );

  test('rotation/done: 409 until every item, trashed ones too, uses the rotated keys', () async {
    final done = rotationDone();
    final host = await queueRotationWithHost();
    expect(
      (await s.post(done, token: w['adam'].accessToken)).status,
      409,
      reason: 'not rotated yet',
    );
    expect((await rotateProdTo2()).status, 204);
    expect(
      (await s.post(done, token: w['adam'].accessToken)).status,
      409,
      reason: 'folder and host still at v1',
    );
    expect((await resealProdFolderAt2()).status, 200);
    await trash(host);
    expect(
      (await s.post(done, token: w['adam'].accessToken)).status,
      409,
      reason: 'trashed items count',
    );
  });

  test(
    'rotation/done: a re-sealed trashed item completes the rotation',
    () async {
      final done = rotationDone();
      final host = await queueRotationWithHost();
      await rotateProdTo2();
      await resealProdFolderAt2();
      await trash(host);
      final seq = await w.orgSeq();
      final resealed = await w.item(
        w['olivia'],
        id: host['id']! as String,
        folder: 'prod',
        keyVersion: 2,
        secret: true,
        deleted: true,
      );
      expect(
        (await w.put(w['olivia'], resealed, 1)).status,
        200,
        reason: 'a trashed item accepts a re-seal',
      );
      expect((await s.post(done, token: w['adam'].accessToken)).status, 204);
      expect(await w.count('pending_rotations'), 0);
      expect(await w.orgSeq(), seq + 1);
    },
  );
}
