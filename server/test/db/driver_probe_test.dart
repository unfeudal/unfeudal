// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('sqlite3 >= 3.35: named @params, RETURNING, upsert, VACUUM INTO an empty file with a bound path', () {
    final v = sqlite3.version.libVersion.split('.').map(int.parse).toList();
    expect(
      v[0] > 3 || (v[0] == 3 && v[1] >= 35),
      isTrue,
      reason: sqlite3.version.libVersion,
    );
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    db.execute('CREATE TABLE t (k TEXT PRIMARY KEY, n BIGINT NOT NULL)');
    db.prepare(
        'INSERT INTO t (k, n) VALUES (@k, @n) ON CONFLICT (k) DO UPDATE SET n = t.n',
      )
      ..executeWith(StatementParameters.named({'@k': 'a', '@n': 1 << 40}))
      ..executeWith(StatementParameters.named({'@k': 'a', '@n': 5}))
      ..close();
    final rows = db
        .prepare('UPDATE t SET n = n + 1 WHERE k = @k RETURNING n')
        .selectWith(StatementParameters.named({'@k': 'a'}));
    expect(rows.single['n'], (1 << 40) + 1);
    final dir = Directory.systemTemp.createTempSync('probe_');
    addTearDown(() => dir.deleteSync(recursive: true));
    // backupDatabase creates it first, mode 0600.
    File('${dir.path}/copy.db').createSync();
    db
        .prepare('VACUUM INTO @p')
        .executeWith(StatementParameters.named({'@p': '${dir.path}/copy.db'}));
    expect(File('${dir.path}/copy.db').lengthSync(), greaterThan(0));
  });

  test('shelf_router mount passes the rest of the path and params', () async {
    final inner = Router()
      ..get(
        '/items/<id>',
        (Request r, String id) => Response.ok('$id ${r.url.path}'),
      );
    final root = Router()..mount('/api/v1/', inner.call);
    final res = await root.call(
      Request('GET', Uri.parse('http://x/api/v1/items/abc')),
    );
    expect(await res.readAsString(), 'abc items/abc');
  });

  final pg = Platform.environment['UNFEUDAL_TEST_POSTGRES_URL'];
  test('postgres v3: pool, named params, transaction settings', () async {
    final u = Uri.parse(pg!);
    final user = u.userInfo.split(':');
    final pool = Pool<void>.withEndpoints(
      [
        Endpoint(
          host: u.host,
          port: u.hasPort ? u.port : 5432,
          database: u.pathSegments.first,
          username: Uri.decodeComponent(user[0]),
          password: user.length > 1 ? Uri.decodeComponent(user[1]) : null,
        ),
      ],
      settings: const PoolSettings(
        maxConnectionCount: 2,
        sslMode: SslMode.disable,
      ),
    );
    addTearDown(pool.close);
    final r = await pool.execute(
      Sql.named('SELECT @n::BIGINT AS n'),
      parameters: {'n': 1 << 40},
    );
    expect(r.single.toColumnMap()['n'], 1 << 40);
    final iso = await pool.runTx(
      (s) async => (await s.execute('SHOW transaction_isolation')).single[0],
      settings: TransactionSettings(
        isolationLevel: IsolationLevel.repeatableRead,
        accessMode: AccessMode.readOnly,
      ),
    );
    expect(iso, 'repeatable read');
    // A void column decodes.
    await pool.runTx(
      (s) => s.execute('SELECT pg_advisory_xact_lock(728403125)'),
    );
  }, skip: pg == null ? 'UNFEUDAL_TEST_POSTGRES_URL not set' : false);
}
