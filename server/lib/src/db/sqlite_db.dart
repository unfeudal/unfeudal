// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:sqlite3/sqlite3.dart';

import 'db.dart';

/// One connection; every statement goes through one FIFO lock, so nothing
/// runs inside another caller's transaction.
class SqliteDb implements Db {
  SqliteDb._(this._db);

  final Database _db;
  Future<void> _tail = Future.value();
  bool _closed = false;

  static SqliteDb open(String path) {
    if (sqlite3.version.versionNumber < 3035000) {
      throw StateError(
        'SQLite >= 3.35 required, found ${sqlite3.version.libVersion}',
      );
    }
    final db = path == ':memory:' ? sqlite3.openInMemory() : sqlite3.open(path);
    // Before the first table; no effect on an existing file.
    db.execute('PRAGMA auto_vacuum = INCREMENTAL');
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA busy_timeout = 5000');
    return SqliteDb._(db);
  }

  @override
  DbEngine get engine => DbEngine.sqlite;

  Future<T> _locked<T>(Future<T> Function() fn) {
    final run = _tail.then((_) => fn());
    _tail = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    Map<String, Object?> params = const {},
  ]) => _locked(() async => _select(sql, params));

  @override
  Future<int> execute(String sql, [Map<String, Object?> params = const {}]) =>
      _locked(() async => _exec(sql, params));

  @override
  Future<T> transaction<T>(
    Future<T> Function(Tx tx) fn, {
    bool readOnly = false,
  }) => _locked(() async {
    // Writers take the write lock at BEGIN; readers keep one WAL snapshot.
    _db.execute(readOnly ? 'BEGIN DEFERRED' : 'BEGIN IMMEDIATE');
    try {
      final result = await fn(_SqliteTx(this));
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  });

  List<Map<String, Object?>> _select(String sql, Map<String, Object?> params) {
    final st = _db.prepare(sql);
    try {
      return [
        for (final r in st.selectWith(StatementParameters.named(_bind(params))))
          Map.of(r),
      ];
    } finally {
      st.close();
    }
  }

  int _exec(String sql, Map<String, Object?> params) {
    final st = _db.prepare(sql);
    try {
      st.executeWith(StatementParameters.named(_bind(params)));
      return _db.updatedRows;
    } finally {
      st.close();
    }
  }

  static Map<String, Object?> _bind(Map<String, Object?> p) => {
    for (final e in p.entries)
      '@${e.key}': switch (e.value) {
        true => 1,
        false => 0,
        final v => v,
      },
  };

  @override
  Future<void> close() => _locked(() async {
    if (!_closed) _db.close();
    _closed = true;
  });
}

/// Runs inside the lock already held by the transaction.
class _SqliteTx implements Tx {
  _SqliteTx(this._db);

  final SqliteDb _db;

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    Map<String, Object?> params = const {},
  ]) async => _db._select(sql, params);

  @override
  Future<int> execute(
    String sql, [
    Map<String, Object?> params = const {},
  ]) async => _db._exec(sql, params);
}
