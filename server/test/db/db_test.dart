// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/db/db.dart';
import 'package:unfeudal_server/src/db/open_db.dart';

import '../support/test_db.dart';

void main() {
  late Db db;
  setUp(() async {
    db = await openTestDb();
    await db.execute(
      'CREATE TABLE kv (k TEXT PRIMARY KEY, n BIGINT NOT NULL, flag INTEGER NOT NULL, note TEXT)',
    );
  });
  tearDown(() => db.close());

  test('named params, BIGINT, bool bound as 1/0, NULL', () async {
    expect(
      await db.execute(
        'INSERT INTO kv (k, n, flag, note) VALUES (@k, @n, @flag, @note)',
        {'k': 'a', 'n': 1 << 40, 'flag': true, 'note': null},
      ),
      1,
    );
    expect(
      (await db.query('SELECT k, n, flag, note FROM kv WHERE k = @k', {
        'k': 'a',
      })).single,
      {'k': 'a', 'n': 1 << 40, 'flag': 1, 'note': null},
    );
  });

  test('execute returns affected rows; RETURNING through query', () async {
    for (final k in ['a', 'b', 'c']) {
      await db.execute('INSERT INTO kv (k, n, flag) VALUES (@k, 0, 0)', {
        'k': k,
      });
    }
    expect(await db.execute('UPDATE kv SET n = n + 1'), 3);
    expect(await db.execute('DELETE FROM kv WHERE k = @k', {'k': 'zz'}), 0);
    expect(
      (await db.query("UPDATE kv SET n = n + 1 WHERE k = 'a' RETURNING n"))
          .single['n'],
      2,
    );
  });

  test('a throwing transaction rolls back and rethrows', () async {
    await expectLater(
      db.transaction((tx) async {
        await tx.execute("INSERT INTO kv (k, n, flag) VALUES ('x', 1, 0)");
        throw StateError('boom');
      }),
      throwsStateError,
    );
    expect(await db.query('SELECT k FROM kv'), isEmpty);
  });

  test('a returning transaction commits and returns its value', () async {
    expect(
      await db.transaction((tx) async {
        await tx.execute("INSERT INTO kv (k, n, flag) VALUES ('y', 7, 0)");
        return 42;
      }),
      42,
    );
    expect((await db.query('SELECT n FROM kv')).single['n'], 7);
  });

  test(
    'concurrent read-modify-write transactions never lose an update',
    () async {
      await db.execute("INSERT INTO kv (k, n, flag) VALUES ('ctr', 0, 0)");
      final got = await Future.wait([
        for (var i = 0; i < 20; i++)
          db.transaction(
            (tx) async =>
                (await tx.query(
                      "UPDATE kv SET n = n + 1 WHERE k = 'ctr' RETURNING n",
                    )).single['n']
                    as int,
          ),
      ]);
      expect(got.toSet(), {for (var i = 1; i <= 20; i++) i});
    },
  );

  test('openDb rejects unknown URLs', () {
    expect(() => openDb('mysql://h/db'), throwsArgumentError);
  });
}
