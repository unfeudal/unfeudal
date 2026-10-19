// SPDX-License-Identifier: AGPL-3.0-or-later
import 'postgres_db.dart';
import 'sqlite_db.dart';

enum DbEngine { sqlite, postgres }

/// Statements with `@name` parameters; booleans are bound as 1/0.
/// Booleans as 1/0, every other value as is.
Object? dbValue(Object? value) => switch (value) {
  true => 1,
  false => 0,
  final other => other,
};

abstract class Tx {
  Future<List<Map<String, Object?>>> query(
    String sql, [
    Map<String, Object?> params = const {},
  ]);

  /// Returns the number of affected rows.
  Future<int> execute(String sql, [Map<String, Object?> params = const {}]);
}

abstract class Db implements Tx {
  DbEngine get engine;

  /// Commits when [fn] returns, rolls back and rethrows when it throws.
  Future<T> transaction<T>(
    Future<T> Function(Tx tx) fn, {
    bool readOnly = false,
  });

  Future<void> close();
}

/// `sqlite::memory:` (tests only), `sqlite:///<path>` or `postgres://…`.
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
