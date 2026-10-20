// SPDX-License-Identifier: AGPL-3.0-or-later
import 'db.dart';
import 'postgres_db.dart';
import 'sqlite_db.dart';

/// `sqlite::memory:` (tests only), `sqlite:///<path>` or `postgres://...`.
Future<Db> openDb(String url) async {
  if (url == 'sqlite::memory:') return SqliteDb.open(':memory:');
  final uri = Uri.parse(url);
  if (url.startsWith('sqlite:///')) {
    // `/C:/data/u.db` is a Windows drive path.
    final path = RegExp(r'^/[A-Za-z]:').hasMatch(uri.path)
        ? uri.path.substring(1)
        : uri.path;
    return SqliteDb.open(path);
  }
  if (uri.scheme == 'postgres') return PostgresDb.open(uri);
  throw ArgumentError.value(uri.scheme, 'url', 'unsupported database');
}
