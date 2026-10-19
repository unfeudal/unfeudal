// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../support/items.dart';
import '../../support/org_world.dart';
import '../../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  setUp(() async {
    s = await TestServer.start();
    w = await OrgWorld.build(
      s,
      roles: {'adam': 'admin', 'mia': 'member', 'max': 'member'},
      folders: {'prod': null},
    );
    await w.acl('prod', 'user:mia', allow: ['view']);
  });
  tearDown(() => s.close());

  Future<TestResponse> revs(TestSession who, Object? id) =>
      s.get('/api/v1/items/$id/revisions', token: who.accessToken);
  List<Object?> numbers(TestResponse r) => [
    for (final i in r.body['revisions']! as List) (i as Map)['revision'],
  ];
  Future<Map<String, Object?>> personal(
    TestSession who, {
    int writes = 3,
  }) async {
    final item = await testItem(who);
    for (var rev = 0; rev < writes; rev++) {
      await s.put(
        '/api/v1/items/${item['id']}',
        token: who.accessToken,
        body: item,
        headers: {'if-match': '$rev'},
      );
    }
    return item;
  }

  test('personal: the owner gets the current item then older versions, newest first; others 404', () async {
    final mia = w['mia'];
    final item = await personal(mia);
    final r = await revs(mia, item['id']);
    expect(numbers(r), [3, 2, 1]);
    expect(
      Item.fromJson((r.body['revisions']! as List).last).updatedBy,
      mia.userId,
    );
    expect(
      [
        (await revs(w['max'], item['id'])).status,
        (await revs(mia, newId())).status,
        (await revs(mia, 'x')).status,
      ],
      [404, 404, 400],
    );
  });

  test(
    'org: admins and view holders; others 404; a folder needs view on itself',
    () async {
      final host = await w.item(w['olivia'], folder: 'prod');
      await w.put(w['olivia'], host, 0);
      await w.put(w['olivia'], host, 1);
      expect(
        [
          numbers(await revs(w['adam'], host['id'])),
          numbers(await revs(w['mia'], host['id'])),
        ],
        [
          [2, 1],
          [2, 1],
        ],
      );
      final zed = await s.createUser('zed@example.org');
      expect(
        [
          (await revs(w['max'], host['id'])).status,
          (await revs(zed, host['id'])).status,
          (await revs(w['mia'], w.folder('prod'))).status,
          (await revs(w['max'], w.folder('prod'))).status,
        ],
        [404, 404, 200, 404],
      );
    },
  );

  test('a purged item answers an empty list', () async {
    final item = await personal(w['mia']);
    await s.db.execute(
      'UPDATE items SET deleted = 1, purged = 1 WHERE id = @i',
      {'i': item['id']},
    );
    expect((await revs(w['mia'], item['id'])).body, {'revisions': <Object?>[]});
  });

  test('item_history off → 404 feature_disabled', () async {
    final off = await TestServer.start(
      env: {'UNFEUDAL_FEATURE_ITEM_HISTORY': 'false'},
    );
    final o = await off.setupOwner();
    expect(
      (await off.get(
        '/api/v1/items/${newId()}/revisions',
        token: o.accessToken,
      )).error,
      'feature_disabled',
    );
    await off.close();
  });
}
