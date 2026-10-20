// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:unfeudal_server/src/db/db.dart';
import 'package:unfeudal_server/src/db/open_db.dart';

/// SQLite in memory; with UNFEUDAL_TEST_POSTGRES_URL a freshly recreated `public` schema
/// (the suite then runs with --concurrency=1). Not migrated: callers run `migrate`.
Future<Db> openTestDb() async {
  final pg = Platform.environment['UNFEUDAL_TEST_POSTGRES_URL'];
  if (pg == null) return openDb('sqlite::memory:');
  final db = await openDb(pg);
  await db.execute('DROP SCHEMA public CASCADE');
  await db.execute('CREATE SCHEMA public');
  return db;
}
