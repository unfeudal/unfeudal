// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/auth/tokens.dart';
import 'package:unfeudal_server/src/db/db.dart';
import 'package:unfeudal_server/src/db/maintenance.dart';
import 'package:unfeudal_server/src/db/migrate.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/test_db.dart';

void main() {
  late Directory dir;
  late Db db;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('unfeudal_maint_');
    db = await openTestDb();
    await migrate(db);
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test(
    'the server secret lives in secret_file (0600), never in the database',
    () async {
      final path = '${dir.path}/secret.key';
      final s = await loadServerSecret(path);
      expect(s, hasLength(32));
      expect(File(path).readAsBytesSync(), s);
      if (!Platform.isWindows) {
        expect(FileStat.statSync(path).modeString(), 'rw-------');
      }
      expect(await loadServerSecret(path), s);
      final values = (await db.query('SELECT value FROM meta'))
          .map((r) => r['value'])
          .join();
      expect(values, isNot(contains(b64(s))));
      File(path).writeAsBytesSync([1, 2, 3]);
      await expectLater(
        loadServerSecret(path),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'instance epoch: 22 base64url chars, stable, replaced by new-epoch',
    () async {
      final e = await ensureInstanceEpoch(db);
      expect(e, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
      expect(await ensureInstanceEpoch(db), e);
      final n = await newInstanceEpoch(db);
      expect(n, isNot(e));
      expect(await ensureInstanceEpoch(db), n);
    },
  );

  test('setup token: generated once, configured one wins, nothing after the first user', () async {
    Future<String?> stored() async =>
        (await db.query(
              "SELECT value FROM meta WHERE key = 'setup_token_hash'",
            )).firstOrNull?['value']
            as String?;
    final t = await ensureSetupToken(db, null);
    expect(t, matches(RegExp(r'^[A-Z2-7]{26}$')));
    expect(await stored(), hashToken(t!));
    expect(
      await ensureSetupToken(db, null),
      isNull,
      reason: 'already pending: not printed again',
    );
    expect(await stored(), hashToken(t));
    expect(await ensureSetupToken(db, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'), isNull);
    expect(await stored(), hashToken('ABCDEFGHIJKLMNOPQRSTUVWXYZ'));
    await db.execute("DELETE FROM meta WHERE key = 'setup_token_hash'");
    await db.execute(
      "INSERT INTO users (id, email, bundle, auth_hash, created_at) "
      "VALUES ('u', 'a@b.c', '{}', 'h', '2026-10-13T12:00:00.000Z')",
    );
    expect(await ensureSetupToken(db, null), isNull);
    expect(await stored(), isNull);
  });

  test('backup: a consistent SQLite copy, never over an existing file; PostgreSQL uses pg_dump', () async {
    if (db.engine == DbEngine.postgres) {
      await expectLater(
        backupDatabase(db, '${dir.path}/b.db'),
        throwsUnsupportedError,
      );
      return;
    }
    final src = await openDb(
      'sqlite:///${dir.path.replaceAll('\\', '/')}/u.db',
    );
    addTearDown(src.close);
    await migrate(src);
    final epoch = await ensureInstanceEpoch(src);
    final target = '${dir.path}/backup.db';
    await backupDatabase(src, target);
    if (!Platform.isWindows) {
      expect(FileStat.statSync(target).modeString(), 'rw-------');
    }
    final copy = await openDb('sqlite:///${target.replaceAll('\\', '/')}');
    expect(
      await ensureInstanceEpoch(copy),
      epoch,
      reason: 'a restored copy keeps its epoch until new-epoch',
    );
    await copy.close();
    await expectLater(
      backupDatabase(src, target),
      throwsA(isA<FileSystemException>()),
    );
  });
}
