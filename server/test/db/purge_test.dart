// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/db/deletion.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/audit.dart';
import '../support/items.dart';
import '../support/org_world.dart';
import '../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  setUp(() async {
    s = await TestServer.start();
    w = await OrgWorld.build(
      s,
      roles: {'mia': 'member'},
      folders: {'prod': null, 'db': 'prod', 'web': null},
    );
    await w.acl('db', 'user:mia', allow: ['view']);
    await w.keys('db', 1, ['olivia', 'mia']);
  });
  tearDown(() => s.close());

  Future<Map<String, Object?>> row(Object? id) async => (await s.db.query(
    'SELECT purged, seq, size, body FROM items WHERE id = @i',
    {'i': id},
  )).single;
  Future<int> counter(String name) async =>
      (await s.db.query('SELECT value FROM counters WHERE name = @n', {
            'n': name,
          })).single['value']!
          as int;
  Future<void> purge(Object? id) =>
      s.db.transaction((tx) => purgeItem(tx, id! as String, s.deps.audit));
  Future<void> put(TestSession who, Map<String, Object?> item, int rev) =>
      s.put(
        '/api/v1/items/${item['id']}',
        token: who.accessToken,
        body: item,
        headers: {'if-match': '$rev'},
      );

  test('a personal item becomes a tombstone: new seq, no payloads, no revisions, createdAt kept, item.purged', () async {
    final o = w['olivia'];
    final item = await testItem(o);
    await put(o, item, 0);
    await put(o, item, 1);
    await put(o, {...item, 'deleted': true}, 2);
    final before = await counter('items_seq');
    final createdAt = (jsonDecode(
      (await row(item['id']))['body']! as String,
    ) as Map<String, Object?>)['createdAt'];
    await purge(item['id']);
    final r = await row(item['id']);
    final body = jsonDecode(r['body']! as String) as Map<String, Object?>;
    expect(
      [
        r['purged'],
        r['seq'],
        body['deleted'],
        body['purged'],
        body['meta'],
        body['secret'],
        body['revision'],
      ],
      [1, before + 1, true, true, null, null, 3],
    );
    expect(createdAt, isNotNull);
    expect(body['createdAt'], createdAt);
    expect(
      [r['size'], Item.fromJson(body).purged],
      [utf8.encode(r['body']! as String).length, true],
    );
    expect(
      await s.db.query(
        'SELECT revision FROM item_revisions WHERE item_id = @i',
        {'i': item['id']},
      ),
      isEmpty,
    );
    expect((await actions(s, 'user:${o.userId}')).last, [
      'item.purged',
      item['id'],
    ]);
  });

  test('an already purged item is left alone', () async {
    final o = w['olivia'];
    final item = await testItem(o);
    await put(o, item, 0);
    await purge(item['id']);
    final seq = (await row(item['id']))['seq'];
    await purge(item['id']);
    expect((await row(item['id']))['seq'], seq);
  });

  test('an org folder takes its subtree: tombstones, ACL, keys, history, pending rotation, org_seq', () async {
    final o = w['olivia'];
    final host = await w.item(o, folder: 'db');
    await w.put(o, host, 0);
    final f = {'o': w.orgId, 'f': w.folder('db')};
    await s.db.execute(
      "INSERT INTO folder_key_history (org_id, folder_id, version, body) VALUES (@o, @f, 1, '{}')",
      f,
    );
    await s.db.execute(
      "INSERT INTO pending_rotations (org_id, folder_id, reason, removed_user_ids) VALUES (@o, @f, 'member_removed', '[]')",
      f,
    );
    final orgSeq = await counter('org_seq');
    await purge(w.folder('prod'));
    expect(
      [
        for (final id in [
          w.folder('prod'),
          w.folder('db'),
          host['id'],
          w.folder('web'),
        ])
          (await row(id))['purged'],
      ],
      [1, 1, 1, 0],
    );
    for (final t in [
      'acl_entries',
      'folder_keys',
      'folder_key_history',
      'pending_rotations',
    ]) {
      expect(await w.count(t), 0, reason: t);
    }
    expect(await counter('org_seq'), orgSeq + 1);
    expect(
      (await actions(s, 'org:${w.orgId}')).reversed.take(3).map((a) => a.first),
      everyElement('item.purged'),
    );
  });

  test('a personal folder takes its subtree', () async {
    final o = w['olivia'];
    final folder = await testItem(o, type: 'folder', meta: {'name': 'a'});
    await put(o, folder, 0);
    final inside = await testItem(o, folderId: folder['id']! as String);
    await put(o, inside, 0);
    await purge(folder['id']);
    expect(
      [
        (await row(folder['id']))['purged'],
        (await row(inside['id']))['purged'],
      ],
      [1, 1],
    );
  });
}
