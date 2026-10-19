// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/db/db.dart';
import 'package:unfeudal_server/src/db/migrate.dart';

import '../support/schema_world.dart';
import '../support/test_db.dart';

/// (query, index on SQLite, index on PostgreSQL). The predicates are those of the routes (sync reads, loadOrg,
/// the retention trash purge); literals stand for the parameters.
const hot = [
  (
    'personal sync',
    "SELECT body FROM items WHERE owner_user_id = 'u1' AND seq > 0 ORDER BY seq LIMIT 501",
    'items_owner_seq',
    'items_owner_seq',
  ),
  (
    'org sync',
    "SELECT body FROM items WHERE org_id = 'o1' AND ((type <> 'folder' AND folder_id IN ('f1')) OR (type = 'folder' AND id IN ('f1'))) AND seq > 0 ORDER BY seq LIMIT 501",
    'items_org_folder_seq',
    'items_org_folder_seq',
  ),
  (
    'membership of a user',
    "SELECT role, status FROM org_members WHERE org_id = 'o1' AND user_id = 'u2'",
    'sqlite_autoindex_org_members_1',
    'org_members_pkey',
  ),
  (
    'teams of a user',
    "SELECT team_id FROM team_members WHERE user_id = 'u2'",
    'team_members_user',
    'team_members_user',
  ),
  (
    'ACL of a folder',
    "SELECT allow, deny FROM acl_entries WHERE folder_id = 'f1'",
    'sqlite_autoindex_acl_entries_1',
    'acl_entries_pkey',
  ),
  (
    'entries of a removed principal',
    "SELECT folder_id FROM acl_entries WHERE principal_type = 'user' AND principal_id = 'u2'",
    'acl_entries_principal',
    'acl_entries_principal',
  ),
  (
    'trash purge',
    "SELECT id FROM items WHERE deleted = 1 AND purged = 0 AND updated_at < '2026-11-01T00:00:00.000Z'",
    'items_trash',
    'items_trash',
  ),
];

Future<String> plan(Db db, String sql) async {
  if (db.engine == DbEngine.sqlite) {
    return (await db.query('EXPLAIN QUERY PLAN $sql'))
        .map((r) => r['detail'])
        .join('\n');
  }
  return db.transaction((tx) async {
    await tx.execute(
      'SET LOCAL enable_seqscan = off',
    ); // tiny tables: without it the planner always scans
    return (await tx.query('EXPLAIN $sql'))
        .map((r) => r.values.first)
        .join('\n');
  });
}

void main() {
  late Db db;
  setUp(() async {
    db = await openTestDb();
    await migrate(db);
    await seedSchema(db);
  });
  tearDown(() => db.close());

  for (final (name, sql, sqliteIndex, pgIndex) in hot) {
    test('$name uses its index', () async {
      expect(
        await plan(db, sql),
        contains(db.engine == DbEngine.sqlite ? sqliteIndex : pgIndex),
      );
    });
  }
}
