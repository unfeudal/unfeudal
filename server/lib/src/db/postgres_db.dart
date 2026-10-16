// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:postgres/postgres.dart';

import 'db.dart';

class PostgresDb implements Db {
  PostgresDb._(this._pool);

  final Pool<void> _pool;
  bool _closed = false;

  /// `sslmode` absent means verify-full.
  static Future<PostgresDb> open(Uri url) async {
    final user = url.userInfo.split(':');
    final sslMode = switch (url.queryParameters['sslmode']) {
      'disable' => SslMode.disable,
      'require' => SslMode.require,
      null || 'verify-full' => SslMode.verifyFull,
      final other => throw ArgumentError.value(other, 'sslmode'),
    };
    final pool = Pool<void>.withEndpoints([
      Endpoint(
        host: url.host,
        port: url.hasPort ? url.port : 5432,
        database: url.pathSegments.first,
        username: user[0].isEmpty ? null : Uri.decodeComponent(user[0]),
        password: user.length > 1 ? Uri.decodeComponent(user[1]) : null,
      ),
    ], settings: PoolSettings(maxConnectionCount: 10, sslMode: sslMode));
    return PostgresDb._(pool);
  }

  @override
  DbEngine get engine => DbEngine.postgres;

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    Map<String, Object?> params = const {},
  ]) => _query(_pool, sql, params);

  @override
  Future<int> execute(String sql, [Map<String, Object?> params = const {}]) =>
      _execute(_pool, sql, params);

  @override
  Future<T> transaction<T>(
    Future<T> Function(Tx tx) fn, {
    bool readOnly = false,
  }) => _pool.runTx(
    (session) => fn(_PostgresTx(session)),
    settings: TransactionSettings(
      isolationLevel: readOnly
          ? IsolationLevel.repeatableRead
          : IsolationLevel.readCommitted,
      accessMode: readOnly ? AccessMode.readOnly : AccessMode.readWrite,
    ),
  );

  /// The cluster should use the C collation; the server warns at start otherwise.
  Future<bool> collationIsC() async {
    final row = (await query(
      'SELECT datcollate, datctype FROM pg_database WHERE datname = current_database()',
    )).single;
    return row['datcollate'] == 'C' && row['datctype'] == 'C';
  }

  @override
  Future<void> close() async {
    if (!_closed) await _pool.close();
    _closed = true;
  }
}

class _PostgresTx implements Tx {
  _PostgresTx(this._session);

  final Session _session;

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    Map<String, Object?> params = const {},
  ]) => _query(_session, sql, params);

  @override
  Future<int> execute(String sql, [Map<String, Object?> params = const {}]) =>
      _execute(_session, sql, params);
}

Future<List<Map<String, Object?>>> _query(
  Session session,
  String sql,
  Map<String, Object?> params,
) async {
  final result = await session.execute(
    Sql.named(sql),
    parameters: _bind(params),
  );
  return [for (final row in result) row.toColumnMap()];
}

Future<int> _execute(
  Session session,
  String sql,
  Map<String, Object?> params,
) async => (await session.execute(
  Sql.named(sql),
  parameters: _bind(params),
)).affectedRows;

Map<String, Object?> _bind(Map<String, Object?> p) => {
  for (final e in p.entries)
    e.key: switch (e.value) {
      true => 1,
      false => 0,
      final v => v,
    },
};
