// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/audit/retention.dart';
import 'package:unfeudal_server/src/db/db.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/items.dart';
import '../support/org_world.dart';
import '../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  setUp(() async {
    s = await TestServer.start();
    w = await OrgWorld.build(s, folders: {'prod': null, 'db': 'prod'});
    await s.db.execute('UPDATE orgs SET settings = @st', {
      'st': '{"trashDays":7}',
    });
  });
  tearDown(() => s.close());

  Future<Object?> purged(Object? id) async => (await s.db.query(
    'SELECT purged FROM items WHERE id = @i',
    {'i': id},
  )).single['purged'];
  Future<Map<String, Object?>> trashed(TestServer on, TestSession who) async {
    final item = await testItem(who);
    await on.put(
      '/api/v1/items/${item['id']}',
      token: who.accessToken,
      body: item,
      headers: {'if-match': '0'},
    );
    await on.put(
      '/api/v1/items/${item['id']}',
      token: who.accessToken,
      body: {...item, 'deleted': true},
      headers: {'if-match': '1'},
    );
    return item;
  }

  test('trash: each scope after its effective trashDays; a folder goes with its subtree', () async {
    final o = w['olivia'];
    final mine = await trashed(s, o);
    final host = await w.item(o, folder: 'db');
    await w.put(o, host, 0);
    await w.put(o, {
      ...await w.item(o, id: w.folder('prod'), type: 'folder'),
      'deleted': true,
    }, 1);
    s.clock.advance(const Duration(days: 8));
    await RetentionJob(s.deps).runOnce();
    expect(
      [
        for (final id in [
          mine['id'],
          w.folder('prod'),
          w.folder('db'),
          host['id'],
        ])
          await purged(id),
      ],
      [0, 1, 1, 1],
    );
    s.clock.advance(const Duration(days: 23));
    await RetentionJob(s.deps).runOnce();
    expect(await purged(mine['id']), 1);
  });

  test('trash_retention_days 0 never purges', () async {
    final keep = await TestServer.start(
      env: {'UNFEUDAL_TRASH_RETENTION_DAYS': '0'},
    );
    final item = await trashed(keep, await keep.setupOwner());
    keep.clock.advance(const Duration(days: 3650));
    await RetentionJob(keep.deps).runOnce();
    expect(
      (await keep.db.query('SELECT purged FROM items WHERE id = @i', {
        'i': item['id'],
      })).single['purged'],
      0,
    );
    await keep.close();
  });

  test('cleanup: ended rate-limit windows, dead refresh tokens, invites stopped for an invite_ttl', () async {
    final t = s.clock.now();
    String ago(Duration d) => iso(t.subtract(d));
    final later = iso(t.add(const Duration(days: 1)));
    for (final (key, start, locked) in [
      ('ip:1', ago(const Duration(days: 2)), null),
      (
        'ip:2',
        ago(const Duration(days: 2)),
        iso(t.add(const Duration(minutes: 5))),
      ),
      ('ip:3', ago(const Duration(minutes: 1)), null),
    ]) {
      await s.db.execute(
        'INSERT INTO login_attempts (key, count, window_start, locked_until) VALUES (@k, 1, @w, @l)',
        {'k': key, 'w': start, 'l': locked},
      );
    }
    for (final (hash, expires, used) in [
      ('a', ago(const Duration(seconds: 1)), null),
      ('b', later, ago(const Duration(days: 8))),
      ('c', later, ago(const Duration(days: 6))),
    ]) {
      await s.db.execute(
        'INSERT INTO refresh_tokens (token_hash, device_id, expires_at, used_at) VALUES (@h, @d, @e, @u)',
        {'h': hash, 'd': w['olivia'].deviceId, 'e': expires, 'u': used},
      );
    }
    final invites = [
      (newId(), ago(const Duration(days: 8)), null, null),
      (newId(), later, ago(const Duration(days: 8)), null),
      (newId(), later, null, ago(const Duration(days: 6))),
      (newId(), later, null, null),
    ];
    for (final (id, expires, accepted, revoked) in invites) {
      await s.db.execute(
        'INSERT INTO invites (id, token_hash, email, created_by, created_at, expires_at, accepted_at, revoked_at) '
        "VALUES (@id, @id, 'x@y.z', @u, @c, @e, @a, @r)",
        {
          'id': id,
          'u': w.io.userId,
          'c': ago(const Duration(days: 10)),
          'e': expires,
          'a': accepted,
          'r': revoked,
        },
      );
    }
    await RetentionJob(s.deps).runOnce();
    expect(
      (await s.db.query(
        "SELECT key FROM login_attempts WHERE key IN ('ip:1', 'ip:2', 'ip:3') ORDER BY key",
      )).map((r) => r['key']),
      ['ip:2', 'ip:3'],
    );
    expect(
      (await s.db.query(
        "SELECT token_hash FROM refresh_tokens WHERE token_hash IN ('a', 'b', 'c')",
      )).map((r) => r['token_hash']),
      ['c'],
    );
    expect(
      (await s.db.query('SELECT id FROM invites ORDER BY id'))
          .map((r) => r['id'])
          .toSet(),
      {invites[2].$1, invites[3].$1},
    );
  });

  test('SQLite: incremental_vacuum hands freed pages back', () async {
    if (s.db.engine != DbEngine.sqlite) return;
    await s.db.execute(
      "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 5000) "
      "INSERT INTO login_attempts (key, count, window_start) SELECT 'x:' || i, 1, @w FROM n",
      {'w': iso(s.clock.now().subtract(const Duration(days: 2)))},
    );
    await RetentionJob(s.deps).runOnce();
    expect((await s.db.query('PRAGMA freelist_count')).single.values.single, 0);
  });

  test('a failing step is logged and the other steps still run', () async {
    final mine = await trashed(s, w['olivia']);
    await s.db.execute('DROP TABLE audit_ips');
    s.clock.advance(const Duration(days: 31));
    await RetentionJob(s.deps).runOnce();
    expect(
      s.logLines.any(
        (l) => l.contains('retention step failed') && l.contains('ips'),
      ),
      isTrue,
    );
    expect(await purged(mine['id']), 1);
  });
}
