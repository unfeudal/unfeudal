// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/db/db.dart';
import 'package:unfeudal_server/src/db/migrate.dart';
import 'package:unfeudal_server/src/db/migration.dart';
import 'package:unfeudal_server/src/db/migrations.dart';
import 'package:unfeudal_server/src/db/open_db.dart';

import '../support/test_db.dart';

Future<String?> version(Db db) async =>
    (await db.query("SELECT value FROM meta WHERE key = 'schema_version'"))
            .firstOrNull?['value']
        as String?;

void main() {
  late Db db;
  setUp(() async => db = await openTestDb());
  tearDown(() => db.close());

  test(
    'a fresh database gets every table, both counters and the locale column',
    () async {
      await migrate(db);
      expect(await version(db), '${migrations.last.version}');
      for (final t in [
        'meta',
        'users',
        'devices',
        'refresh_tokens',
        'login_attempts',
        'counters',
        'orgs',
        'items',
        'item_revisions',
        'org_members',
        'teams',
        'team_members',
        'acl_entries',
        'folder_keys',
        'folder_key_history',
        'invites',
        'pending_rotations',
        'audit_events',
        'audit_heads',
        'audit_ips',
      ]) {
        await db.query('SELECT count(*) AS n FROM $t');
      }
      expect(await db.query('SELECT name, value FROM counters ORDER BY name'), [
        {'name': 'items_seq', 'value': 0},
        {'name': 'org_seq', 'value': 0},
      ]);
      await db.execute(
        "INSERT INTO users (id, email, bundle, auth_hash, created_at) VALUES ('u', 'a@b.c', '{}', 'h', '2026-10-13T12:00:00.000Z')",
      );
      expect(
        (await db.query('SELECT locale, bundle_version FROM users')).single,
        {'locale': 'en', 'bundle_version': 0},
      );
    },
  );

  test('migrate is idempotent and resumes a partial database', () async {
    await migrate(db, migrations.sublist(0, 2));
    expect(await version(db), '2');
    await migrate(db);
    await migrate(db);
    expect(await version(db), '4');
    expect(
      (await db.query(
        "SELECT count(*) AS n FROM counters WHERE name = 'org_seq'",
      )).single['n'],
      1,
    );
  });

  test('a failing migration rolls back entirely', () async {
    final broken = [
      ...migrations,
      const Migration(5, ['CREATE TABLE z (a TEXT)', 'NOT SQL']),
    ];
    await expectLater(migrate(db, broken), throwsA(anything));
    expect(await version(db), '4');
    await expectLater(db.query('SELECT * FROM z'), throwsA(anything));
  });

  test('a newer database is refused with SchemaTooNew', () async {
    await migrate(db);
    await db.execute(
      "UPDATE meta SET value = '99' WHERE key = 'schema_version'",
    );
    await expectLater(
      migrate(db),
      throwsA(
        isA<SchemaTooNew>().having((e) => (e.found, e.supported), 'versions', (
          99,
          migrations.last.version,
        )),
      ),
    );
  });

  final pg = Platform.environment['UNFEUDAL_TEST_POSTGRES_URL'];
  test(
    'two instances migrating at once both succeed (advisory lock)',
    () async {
      final other = await openDb(pg!);
      addTearDown(other.close);
      await Future.wait([migrate(db), migrate(other)]);
      expect(await version(db), '4');
    },
    skip: pg == null ? 'PostgreSQL only' : false,
  );
}
