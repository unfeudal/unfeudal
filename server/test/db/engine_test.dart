// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:unfeudal_server/src/db/db.dart';
import 'package:unfeudal_server/src/db/migrate.dart';
import 'package:unfeudal_server/src/db/open_db.dart';
import 'package:unfeudal_server/src/db/postgres_db.dart';

import '../support/test_db.dart';

void main() {
  group('SQLite file', () {
    late Directory dir;
    late String path;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('unfeudal_engine_');
      path = '${dir.path}/u.db'.replaceAll('\\', '/');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test(
      'per-connection settings, incremental auto_vacuum from the first table',
      () async {
        for (var i = 0; i < 2; i++) {
          final db = await openDb('sqlite:///$path');
          await migrate(db);
          Future<Object?> pragma(String p) async =>
              (await db.query('PRAGMA $p')).single.values.single;
          expect(await pragma('foreign_keys'), 1);
          expect(await pragma('journal_mode'), 'wal');
          expect(await pragma('busy_timeout'), 5000);
          expect(await pragma('auto_vacuum'), 2);
          await db.close();
        }
      },
    );

    test(
      'writes take the write lock at BEGIN; reads run beside a writer',
      () async {
        final db = await openDb('sqlite:///$path');
        addTearDown(db.close);
        await migrate(db);
        final other = sqlite3.open(path)..execute('BEGIN IMMEDIATE');
        addTearDown(other.close);
        expect(
          await db.transaction(
            readOnly: true,
            (tx) async =>
                (await tx.query('SELECT count(*) AS n FROM users')).single['n'],
          ),
          0,
        );
        final sw = Stopwatch()..start();
        await expectLater(
          db.transaction((tx) async => 1),
          throwsA(isA<SqliteException>()),
        );
        expect(
          sw.elapsed,
          greaterThan(const Duration(seconds: 4)),
          reason: 'busy_timeout 5000',
        );
        other.execute('ROLLBACK');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  test('a read-only transaction sees one snapshot', () async {
    final db = await openTestDb();
    addTearDown(db.close);
    await db.execute(
      'CREATE TABLE kv (k TEXT PRIMARY KEY, n BIGINT NOT NULL, flag INTEGER NOT NULL)',
    );
    final (first, second, writer) = await db.transaction(readOnly: true, (
      tx,
    ) async {
      final a = (await tx.query('SELECT count(*) AS n FROM kv')).single['n'];
      final w = db.execute("INSERT INTO kv (k, n, flag) VALUES ('late', 0, 0)");
      // SQLite: the write is queued behind this transaction.
      if (db.engine == DbEngine.postgres) await w;
      final b = (await tx.query('SELECT count(*) AS n FROM kv')).single['n'];
      return (a, b, w);
    });
    await writer;
    expect(first, second);
    expect((await db.query('SELECT count(*) AS n FROM kv')).single['n'], 1);
  });

  test('foreign keys are enforced', () async {
    final db = await openTestDb();
    addTearDown(db.close);
    await migrate(db);
    await expectLater(
      db.execute(
        "INSERT INTO devices (id, user_id, name, platform, created_at, last_seen_at) "
        "VALUES ('d', 'nobody', 'n', 'linux', '2026-10-13T12:00:00.000Z', '2026-10-13T12:00:00.000Z')",
      ),
      throwsA(anything),
    );
  });

  final pg = Platform.environment['UNFEUDAL_TEST_POSTGRES_URL'];
  test('PostgreSQL: READ COMMITTED writes, REPEATABLE READ READ ONLY reads, C collation', () async {
    final db = await openTestDb() as PostgresDb;
    addTearDown(db.close);
    expect(
      await db.transaction(
        (tx) async =>
            (await tx.query('SHOW transaction_isolation')).single.values.single,
      ),
      'read committed',
    );
    expect(
      await db.transaction(
        readOnly: true,
        (tx) async => [
          (await tx.query('SHOW transaction_isolation')).single.values.single,
          (await tx.query('SHOW transaction_read_only')).single.values.single,
        ],
      ),
      ['repeatable read', 'on'],
    );
    expect(
      await db.collationIsC(),
      isTrue,
      reason: 'CI creates the cluster with --locale=C',
    );
  }, skip: pg == null ? 'PostgreSQL only' : false);
}
