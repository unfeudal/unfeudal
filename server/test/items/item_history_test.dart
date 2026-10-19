// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:test/test.dart';

import '../support/audit.dart';
import '../support/items.dart';
import '../support/org_world.dart';
import '../support/test_server.dart';

void main() {
  group('personal', () {
    late TestServer s;
    late TestSession o;
    setUp(() async {
      s = await TestServer.start(
        env: {'UNFEUDAL_ITEM_HISTORY_MAX_VERSIONS': '2'},
      );
      o = await s.setupOwner();
    });
    tearDown(() => s.close());

    Future<TestResponse> put(Map<String, Object?> item, int ifMatch) => s.put(
      '/api/v1/items/${item['id']}',
      token: o.accessToken,
      body: item,
      headers: {'if-match': '$ifMatch'},
    );
    Future<List<Object?>> revisions(Object? id) async => [
      for (final r in await s.db.query(
        'SELECT revision FROM item_revisions WHERE item_id = @i ORDER BY revision',
        {'i': id},
      ))
        r['revision'],
    ];

    test(
      'each update stores the replaced version, pruned to the effective max',
      () async {
        final item = await testItem(o);
        for (var rev = 0; rev < 4; rev++) {
          expect((await put(item, rev)).status, 200);
        }
        expect(await revisions(item['id']), [2, 3]);
        final row = (await s.db.query(
          'SELECT body, size FROM item_revisions WHERE item_id = @i AND revision = 3',
          {'i': item['id']},
        )).single;
        expect(jsonDecode(row['body']! as String)['revision'], 3);
        expect(row['size'], utf8.encode(row['body']! as String).length);
      },
    );

    test('item_history off: no revision stored', () async {
      final off = await TestServer.start(
        env: {'UNFEUDAL_FEATURE_ITEM_HISTORY': 'false'},
      );
      final owner = await off.setupOwner();
      final item = await testItem(owner);
      for (var rev = 0; rev < 2; rev++) {
        await off.put(
          '/api/v1/items/${item['id']}',
          token: owner.accessToken,
          body: item,
          headers: {'if-match': '$rev'},
        );
      }
      expect(await off.db.query('SELECT item_id FROM item_revisions'), isEmpty);
      await off.close();
    });

    test('created, updated, moved [id, old, new], deleted, restored in user:<caller>, actor = caller', () async {
      final folder = await testItem(o, type: 'folder', meta: {'name': 'a'});
      final f = folder['id']! as String;
      await put(folder, 0);
      final host = await testItem(o);
      final id = host['id']! as String;
      await put(host, 0);
      await put(host, 1);
      final moved = await testItem(o, id: id, folderId: f);
      await put(moved, 2);
      await put({...moved, 'deleted': true}, 3);
      await put(moved, 4);
      expect((await actions(s, 'user:${o.userId}')).skip(1), [
        ['item.created', f],
        ['item.created', id],
        ['item.updated', id],
        ['item.moved', id, 'root', f],
        ['item.deleted', id, f],
        ['item.restored', id, f],
      ]);
      final last = (await auditEvents(s, 'user:${o.userId}')).last;
      expect([last.actorUser, last.actorDevice], [o.userId, o.deviceId]);
    });
  });

  group('org', () {
    late TestServer s;
    late OrgWorld w;
    setUp(() async {
      s = await TestServer.start();
      w = await OrgWorld.build(s, folders: {'prod': null});
      await s.db.execute('UPDATE orgs SET settings = @st', {
        'st': '{"maxVersions":1}',
      });
    });
    tearDown(() => s.close());

    test('events in org:<id>; the org maxVersions is stricter than the server value', () async {
      final host = await w.item(w['olivia'], folder: 'prod');
      for (var rev = 0; rev < 3; rev++) {
        expect((await w.put(w['olivia'], host, rev)).status, 200);
      }
      expect(
        (await s.db.query(
          'SELECT revision FROM item_revisions WHERE item_id = @i',
          {'i': host['id']},
        )).map((r) => r['revision']),
        [2],
      );
      expect((await actions(s, 'org:${w.orgId}')).last, [
        'item.updated',
        host['id'],
        w.folder('prod'),
      ]);
      expect(await actions(s, 'user:${w.id('olivia')}'), [
        ['device.added', w['olivia'].deviceId],
      ]);
    });
  });
}
