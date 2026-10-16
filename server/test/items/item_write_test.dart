// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/items.dart';
import '../support/test_server.dart';

void main() {
  late TestServer s;
  late TestSession owner;
  setUp(() async {
    s = await TestServer.start(env: {'UNFEUDAL_MAX_VAULT_SIZE': '8KB'});
    owner = await s.setupOwner();
  });
  tearDown(() => s.close());

  Future<TestResponse> put(
    TestSession who,
    Map<String, Object?> item,
    Object ifMatch, {
    String? path,
  }) => s.put(
    '/api/v1/items/${path ?? item['id']}',
    token: who.accessToken,
    body: item,
    headers: {'if-match': '$ifMatch'},
  );
  Future<Map<String, Object?>> row(String id) async => (await s.db.query(
    'SELECT owner_user_id, revision, seq, size, body FROM items WHERE id = @id',
    {'id': id},
  )).single;
  Future<Map<String, Object?>> created(Map<String, Object?> item) async {
    final r = await put(owner, item, 0);
    expect(r.status, 200, reason: '${r.json}');
    return r.body;
  }

  test('create then update: server fields, revision, seq from items_seq, size of the stored body', () async {
    final item = {
      'pinnedBy': 'future',
      ...await testItem(owner),
      'purged': true,
      'revision': 99,
      'updatedBy': newId(),
      'createdAt': '2020-01-01T00:00:00.000Z',
    };
    final stored = await created(item);
    final createdAt = iso(s.clock.now());
    expect(
      (
        stored['revision'],
        stored['updatedBy'],
        stored['updatedDevice'],
        stored['createdAt'],
        stored['updatedAt'],
      ),
      (1, owner.userId, owner.deviceId, createdAt, createdAt),
    );
    expect(
      (stored['pinnedBy'], stored.containsKey('purged'), stored.keys.first),
      ('future', false, 'pinnedBy'),
    );
    final r = await row(item['id']! as String);
    expect((r['owner_user_id'], r['revision'], r['seq']), (owner.userId, 1, 1));
    expect(jsonDecode(r['body']! as String), stored);
    expect(r['size'], utf8.encode(r['body']! as String).length);
    Item.fromJson(stored);
    s.clock.advance(const Duration(minutes: 1));
    final updated = await put(owner, {...item, 'deleted': true}, 1);
    expect(
      (updated.body['revision'], (await row(item['id']! as String))['seq']),
      (2, 2),
    );
    expect(
      (updated.body['createdAt'], updated.body['updatedAt']),
      (createdAt, iso(s.clock.now())),
    );
    expect(
      (await s.db.query('SELECT created_at FROM items WHERE id = @id', {
        'id': item['id'],
      })).single['created_at'],
      createdAt,
    );
  });

  test('a stale If-Match is 409 with the current item', () async {
    final item = await testItem(owner);
    final stored = await created(item);
    for (final stale in [0, 2, 7]) {
      final r = await put(owner, item, stale);
      expect((r.status, r.error), (409, 'conflict'), reason: '$stale');
      expect(r.body['item'], stored);
    }
    final missing = await put(owner, await testItem(owner), 3);
    expect((missing.status, missing.body['item']), (409, null));
    expect((await row(item['id']! as String))['revision'], 1);
    expect(
      (await s.db.query("SELECT value FROM counters WHERE name = 'items_seq'"))
          .single['value'],
      1,
      reason: 'rolled back',
    );
  });

  test('another account\'s item is 403 and unchanged', () async {
    final bob = await s.createUser('bob@example.org');
    final item = await testItem(owner);
    final stored = await created(item);
    for (final ifMatch in [0, 1, 2]) {
      expect(
        (await put(
          bob,
          await testItem(bob, id: item['id']! as String),
          ifMatch,
        )).status,
        403,
      );
    }
    expect(
      jsonDecode((await row(item['id']! as String))['body']! as String),
      stored,
    );
  });

  test('another account\'s tombstone or item type is never revealed: 403 without body', () async {
    final bob = await s.createUser('bob@example.org');
    final item = await testItem(owner);
    final stored = await created(item);
    final typed = await put(
      bob,
      await testItem(bob, id: item['id']! as String, type: 'identity'),
      1,
    );
    expect(
      (typed.status, typed.body.containsKey('item')),
      (403, false),
      reason: 'ownership before the type check',
    );
    await s.db.execute(
      'UPDATE items SET purged = 1, deleted = 1, body = @b WHERE id = @id',
      {
        'b': jsonEncode({
          ...stored,
          'deleted': true,
          'purged': true,
          'meta': null,
          'secret': null,
        }),
        'id': item['id'],
      },
    );
    final tomb = await put(
      bob,
      await testItem(bob, id: item['id']! as String),
      0,
    );
    expect(
      (tomb.status, tomb.body.containsKey('item')),
      (403, false),
      reason: 'ownership before the tombstone check',
    );
  });

  test('a tombstone refuses every write with 409 and itself', () async {
    final item = await testItem(owner);
    final stored = await created(item);
    final tomb = {
      ...stored,
      'deleted': true,
      'purged': true,
      'meta': null,
      'secret': null,
    };
    await s.db.execute(
      'UPDATE items SET purged = 1, deleted = 1, body = @b WHERE id = @id',
      {'b': jsonEncode(tomb), 'id': item['id']},
    );
    for (final ifMatch in [0, 1, 2]) {
      final r = await put(owner, item, ifMatch);
      expect(r.status, 409, reason: '$ifMatch');
      expect(r.body['item'], tomb);
    }
  });

  test(
    'type is fixed; secret null keeps the stored one; a move must re-seal it',
    () async {
      final id = newId();
      final folder = await testItem(owner, type: 'folder');
      await created(folder);
      final identity = await testItem(
        owner,
        id: id,
        type: 'identity',
        secret: true,
      );
      final stored = await created(identity);
      expect((await put(owner, {...identity, 'type': 'host'}, 1)).status, 400);
      final kept = await put(owner, {...identity, 'secret': null}, 1);
      expect(kept.status, 200);
      expect(kept.body['secret'], stored['secret']);
      final moved = await testItem(
        owner,
        id: id,
        type: 'identity',
        folderId: folder['id']! as String,
      );
      expect((await put(owner, {...moved, 'secret': null}, 2)).status, 400);
      final resealed = await testItem(
        owner,
        id: id,
        type: 'identity',
        folderId: folder['id']! as String,
        secret: true,
      );
      expect((await put(owner, resealed, 2)).status, 200);
    },
  );

  test('folderId must be a live folder of the caller', () async {
    final bob = await s.createUser('bob@example.org');
    final bobFolder = await testItem(bob, type: 'folder');
    expect((await put(bob, bobFolder, 0)).status, 200);
    final host = await testItem(owner);
    await created(host);
    final purged = await testItem(owner, type: 'folder');
    await created(purged);
    await s.db.execute('UPDATE items SET purged = 1 WHERE id = @id', {
      'id': purged['id'],
    });
    for (final parent in [newId(), bobFolder['id'], host['id'], purged['id']]) {
      expect(
        (await put(
          owner,
          await testItem(owner, folderId: parent! as String),
          0,
        )).status,
        400,
        reason: '$parent',
      );
    }
    final mine = await testItem(owner, type: 'folder');
    await created(mine);
    expect(
      (await put(
        owner,
        await testItem(owner, folderId: mine['id']! as String),
        0,
      )).status,
      200,
    );
  });

  test('a folder under itself or a descendant is 400', () async {
    final a = await testItem(owner, type: 'folder');
    await created(a);
    final b = await testItem(
      owner,
      type: 'folder',
      folderId: a['id']! as String,
    );
    await created(b);
    final aUnderB = await testItem(
      owner,
      id: a['id']! as String,
      type: 'folder',
      folderId: b['id']! as String,
    );
    final aUnderA = await testItem(
      owner,
      id: a['id']! as String,
      type: 'folder',
      folderId: a['id']! as String,
    );
    expect(
      (
        (await put(owner, aUnderB, 1)).status,
        (await put(owner, aUnderA, 1)).status,
      ),
      (400, 400),
    );
  });

  test('request validation is 400 before any write', () async {
    final item = await testItem(owner);
    expect((await put(owner, item, 0, path: 'NOT-A-UUID')).status, 400);
    expect(
      (await s.put(
        '/api/v1/items/${item['id']}',
        token: owner.accessToken,
        body: item,
      )).status,
      400,
      reason: 'If-Match missing',
    );
    for (final ifMatch in ['abc', '-1', '1234567890123456']) {
      expect((await put(owner, item, ifMatch)).status, 400);
    }
    for (final over in <Map<String, Object?>>[
      {'id': newId()},
      {'type': ''},
      {'type': 'x' * 65},
      {'schemaVersion': 0},
      {'deleted': 'no'},
      {
        'meta': {'v': 1},
      },
      {'meta': null},
      {'secret': 'x'},
      {'folderId': 'f'},
      {'scope': 'team'},
      {'orgId': newId()},
      {'scope': 'org'},
    ]) {
      expect(
        (await put(
          owner,
          {...item, ...over},
          0,
          path: item['id']! as String,
        )).status,
        400,
        reason: '$over',
      );
    }
    for (final t in ['knownHost', 'profile', 'hostBinding', 'memberPin']) {
      final folder = await testItem(owner, type: 'folder');
      expect(
        (await put(
          owner,
          await testItem(owner, type: t, folderId: folder['id']! as String),
          0,
        )).status,
        400,
        reason: t,
      );
    }
    expect(await s.db.query('SELECT id FROM items'), isEmpty);
    expect(
      (await s.put(
        '/api/v1/items/${item['id']}',
        body: item,
        headers: {'if-match': '0'},
      )).status,
      401,
    );
  });

  test('trashed items accept only a restore or a re-seal', () async {
    final folder = await testItem(owner, type: 'folder');
    await created(folder);
    final fid = folder['id']! as String;
    final host = await testItem(owner, folderId: fid);
    await created(host);
    expect((await put(owner, {...folder, 'deleted': true}, 1)).status, 200);
    final hid = host['id']! as String;
    final reseal = await testItem(
      owner,
      id: hid,
      folderId: fid,
      meta: {'name': 'renamed'},
    );
    expect(
      (await put(owner, reseal, 1)).status,
      200,
      reason: 're-seal: same folder, same deleted',
    );
    expect((await put(owner, {...reseal, 'deleted': true}, 2)).status, 400);
    final other = await testItem(owner, type: 'folder', deleted: true);
    await created(other);
    expect(
      (await put(
        owner,
        await testItem(owner, id: hid, folderId: other['id']! as String),
        2,
      )).status,
      400,
      reason: 'from one trashed folder to another',
    );
    expect(
      (await put(owner, await testItem(owner, id: hid), 2)).status,
      200,
      reason: 'moved out: restore',
    );
    expect(
      (await put(owner, {...folder, 'deleted': false}, 2)).status,
      200,
      reason: 'deleted true → false: restore',
    );
  });

  test('a write over the vault quota is 413, revisions counted; with item_history an update counts the revision it adds', () async {
    final a = await testItem(owner);
    final stored = await created(a);
    final size = (await row(a['id']! as String))['size']! as int;
    await s.db.execute(
      "INSERT INTO item_revisions (item_id, revision, body, size, created_at) VALUES (@id, 0, '{}', @n, @t)",
      {'id': a['id'], 'n': 8192 - 2 * size + 1, 't': iso(s.clock.now())},
    );
    final b = await put(owner, await testItem(owner), 0);
    expect((b.status, b.error), (413, 'payload_too_large'));
    final same = await put(owner, {...a, 'meta': stored['meta']}, 1);
    expect(
      (same.status, same.error),
      (413, 'payload_too_large'),
      reason: 'same size, but the replaced version becomes a revision',
    );
    await s.db.execute('DELETE FROM item_revisions');
    expect((await put(owner, {...a, 'meta': stored['meta']}, 1)).status, 200);
  });

  test(
    'item_history off: a write that does not grow passes over the quota',
    () async {
      final off = await TestServer.start(
        env: {
          'UNFEUDAL_MAX_VAULT_SIZE': '8KB',
          'UNFEUDAL_FEATURE_ITEM_HISTORY': 'false',
        },
      );
      addTearDown(off.close);
      final o = await off.setupOwner();
      final a = await testItem(o);
      final stored = (await off.put(
        '/api/v1/items/${a['id']}',
        token: o.accessToken,
        body: a,
        headers: {'if-match': '0'},
      )).body;
      await off.db.execute(
        "INSERT INTO item_revisions (item_id, revision, body, size, created_at) VALUES (@id, 0, '{}', 8192, @t)",
        {'id': a['id'], 't': iso(off.clock.now())},
      );
      final r = await off.put(
        '/api/v1/items/${a['id']}',
        token: o.accessToken,
        body: {...a, 'meta': stored['meta']},
        headers: {'if-match': '1'},
      );
      expect(r.status, 200);
    },
  );

  test('org items: orgs off is 404 feature_disabled; no confirmed membership is 404', () async {
    final org = newId(), folder = newId();
    final item = await testItem(
      owner,
      type: 'folder',
      id: folder,
      scope: 'org',
      orgId: org,
    );
    final r = await put(owner, item, 0);
    expect((r.status, r.error), (404, 'not_found'));
    final off = await TestServer.start(env: {'UNFEUDAL_FEATURE_ORGS': 'false'});
    addTearDown(off.close);
    final o = await off.setupOwner();
    final r2 = await off.put(
      '/api/v1/items/$folder',
      token: o.accessToken,
      body: item,
      headers: {'if-match': '0'},
    );
    expect((r2.status, r2.error), (404, 'feature_disabled'));
  });
}
