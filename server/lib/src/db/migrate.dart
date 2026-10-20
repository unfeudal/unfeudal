// SPDX-License-Identifier: AGPL-3.0-or-later
import 'db.dart';
import 'maintenance.dart';
import 'migration.dart';
import 'migrations.dart';

/// The database was migrated by a newer server: refuse to start rather than run against an unknown schema.
class SchemaTooNew implements Exception {
  const SchemaTooNew(this.found, this.supported);

  final int found;
  final int supported;

  @override
  String toString() =>
      'Database schema $found is newer than this server ($supported). '
      'Upgrade the server or restore a backup.';
}

const _advisoryKey = 728403125;

/// One transaction per migration; the applied version is the `meta` row
/// `schema_version`, written in the same transaction.
Future<void> migrate(Db db, [List<Migration> all = migrations]) async {
  final supported = all.last.version;
  final found = await _applied(db, db.engine);
  if (found > supported) throw SchemaTooNew(found, supported);
  for (final m in all) {
    await db.transaction((tx) async {
      if (db.engine == DbEngine.postgres) {
        await tx.query('SELECT pg_advisory_xact_lock($_advisoryKey)');
      }
      // Re-read after the lock: another instance may have run it.
      final applied = await _applied(tx, db.engine);
      if (applied > supported) throw SchemaTooNew(applied, supported);
      if (applied >= m.version) return;
      for (final s in m.statements) {
        await tx.execute(s);
      }
      await setMeta(tx, 'schema_version', '${m.version}');
    });
  }
}

Future<int> _applied(Tx tx, DbEngine engine) async {
  final present = engine == DbEngine.sqlite
      ? (await tx.query(
              "SELECT count(*) AS n FROM sqlite_master WHERE type = 'table' AND name = 'meta'",
            )).single['n'] ==
            1
      // A catalog scan, not to_regclass: its cache can miss a table another instance just committed.
      : (await tx.query(
              "SELECT count(*) AS n FROM pg_tables WHERE schemaname = current_schema() AND tablename = 'meta'",
            )).single['n'] ==
            1;
  if (!present) return 0;
  final rows = await tx.query(
    "SELECT value FROM meta WHERE key = 'schema_version'",
  );
  return rows.isEmpty ? 0 : int.parse(rows.single['value']! as String);
}
