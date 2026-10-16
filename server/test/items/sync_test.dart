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
    s = await TestServer.start();
    owner = await s.setupOwner();
  });
  tearDown(() => s.close());

  Future<TestResponse> put(
    TestSession who,
    Map<String, Object?> item,
    int ifMatch,
  ) => s.put(
    '/api/v1/items/${item['id']}',
    token: who.accessToken,
    body: item,
    headers: {'if-match': '$ifMatch'},
  );
  Future<SyncPage> sync(TestSession who, [String query = '']) async {
    final r = await s.get('/api/v1/sync$query', token: who.accessToken);
    expect(r.status, 200, reason: '${r.json}');
    expect(
      r.body.containsKey('org'),
      isFalse,
      reason: 'no org block for personal-only sync',
    );
    return SyncPage.fromJson(r.json);
  }

  test(
    'own items after the cursor, in seq order; empty page keeps the cursor',
    () async {
      final items = [for (var i = 0; i < 3; i++) await testItem(owner)];
      for (final i in items) {
        await put(owner, i, 0);
      }
      final all = await sync(owner);
      expect(all.items.map((i) => i.id), items.map((i) => i['id']));
      expect((all.cursor, all.more), (3, false));
      expect(
        (await sync(owner, '?cursor=2')).items.single.id,
        items.last['id'],
      );
      final empty = await sync(owner, '?cursor=3');
      expect(empty.items, isEmpty);
      expect(empty.cursor, 3);
    },
  );

  test('pages of 500 with more', () async {
    for (var i = 1; i <= 501; i++) {
      final body = {
        ...await testItem(owner),
        'revision': 1,
        'createdAt': iso(s.clock.now()),
        'updatedAt': iso(s.clock.now()),
        'updatedBy': owner.userId,
        'updatedDevice': owner.deviceId,
      };
      await s.db.execute(
        'INSERT INTO items (id, owner_user_id, type, revision, body, size, created_at, updated_at, seq) '
        "VALUES (@id, @u, 'host', 1, @b, 1, @t, @t, @seq)",
        {
          'id': body['id'],
          'u': owner.userId,
          'b': jsonEncode(body),
          't': iso(s.clock.now()),
          'seq': i,
        },
      );
    }
    await s.db.execute(
      "UPDATE counters SET value = 501 WHERE name = 'items_seq'",
    );
    final first = await sync(owner);
    expect((first.items.length, first.cursor, first.more), (500, 500, true));
    final second = await sync(owner, '?cursor=500');
    expect((second.items.length, second.cursor, second.more), (1, 501, false));
  });

  test(
    'another account\'s items never appear; trash and tombstones do',
    () async {
      final bob = await s.createUser('bob@example.org');
      await put(bob, await testItem(bob), 0);
      final trashed = await testItem(owner, deleted: true);
      await put(owner, trashed, 0);
      final tomb = await testItem(owner);
      final stored = (await put(owner, tomb, 0)).body;
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
          'id': tomb['id'],
        },
      );
      final page = await sync(owner);
      expect(page.items.map((i) => (i.id, i.deleted, i.purged)), [
        (trashed['id'], true, false),
        (tomb['id'], true, true),
      ]);
      expect((await sync(bob)).items, hasLength(1));
    },
  );

  test('cursor_ahead when a cursor passes items_seq or org_seq; orgs off ignores orgCursor', () async {
    for (final q in ['?cursor=1', '?orgCursor=1']) {
      final r = await s.get('/api/v1/sync$q', token: owner.accessToken);
      expect(
        (r.status, r.error, r.body['reason']),
        (409, 'conflict', 'cursor_ahead'),
        reason: q,
      );
    }
    final off = await TestServer.start(env: {'UNFEUDAL_FEATURE_ORGS': 'false'});
    addTearDown(off.close);
    final o = await off.setupOwner();
    expect(
      (await off.get('/api/v1/sync?orgCursor=9', token: o.accessToken)).status,
      200,
    );
  });

  test('cursors must be ints ≥ 0; the route needs a token', () async {
    for (final q in [
      '?cursor=-1',
      '?cursor=x',
      '?cursor=1.5',
      '?orgCursor=-2',
      '?cursor=',
    ]) {
      expect(
        (await s.get('/api/v1/sync$q', token: owner.accessToken)).status,
        400,
        reason: q,
      );
    }
    expect((await s.get('/api/v1/sync')).status, 401);
  });

  test('last_seen_at is written at most every 5 min', () async {
    Future<Object?> seen() async => (await s.db.query(
      'SELECT last_seen_at FROM devices WHERE id = @d',
      {'d': owner.deviceId},
    )).single['last_seen_at'];
    final start = await seen();
    s.clock.advance(const Duration(minutes: 4));
    await sync(owner);
    expect(await seen(), start);
    s.clock.advance(const Duration(minutes: 2));
    await sync(owner);
    expect(await seen(), iso(s.clock.now()));
  });

  test(
    'concurrent writes get distinct seqs and pages return them in seq order',
    () async {
      final bob = await s.createUser('bob@example.org');
      final writes = [
        for (var i = 0; i < 30; i++)
          (i.isEven ? owner : bob, await testItem(i.isEven ? owner : bob)),
      ];
      final results = await Future.wait([
        for (final (who, item) in writes) put(who, item, 0),
      ]);
      expect(results.every((r) => r.status == 200), isTrue);
      final seqs = (await s.db.query('SELECT seq FROM items ORDER BY seq'))
          .map((r) => r['seq'])
          .toList();
      expect(seqs, [for (var i = 1; i <= 30; i++) i]);
      final mine = await sync(owner);
      expect(mine.items, hasLength(15));
      final shared = await testItem(owner);
      await put(owner, shared, 0);
      final race = await Future.wait([
        for (var i = 0; i < 5; i++)
          put(owner, {...shared, 'deleted': i.isEven}, 1),
      ]);
      expect(race.where((r) => r.status == 200), hasLength(1));
      expect(race.where((r) => r.status == 409), hasLength(4));
    },
  );
}
