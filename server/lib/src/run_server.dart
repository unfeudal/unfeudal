// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'api/app.dart';
import 'config/config.dart';
import 'db/db.dart';
import 'db/maintenance.dart';
import 'db/migrate.dart';
import 'db/postgres_db.dart';
import 'log/logger.dart';

class RunningServer {
  RunningServer(this.port, this._close);

  final int port;
  final Future<void> Function() _close;

  Future<void> close() => _close();
}

/// Opens and migrates the database (a newer schema refuses to start), prints
/// the setup token once, then serves.
Future<RunningServer> runServer(Config config, {Logger? log}) async {
  log ??= Logger(config.logLevel, stdout.writeln);
  final db = await openDb(config.databaseUrl);
  try {
    await migrate(db);
    if (db is PostgresDb && !await db.collationIsC()) {
      log.warn(
        "database collation is not C: create it with TEMPLATE template0 LC_COLLATE 'C' LC_CTYPE 'C'",
      );
    }
    final deps = await AppDeps.create(config, db, log: log);
    final token = await ensureSetupToken(db, config.setupToken);
    // Printed once, raw: redaction would hide it.
    if (token != null) log.sink('Setup token: ${groupSetupToken(token)}');
    final server = await shelf_io.serve(
      buildHandler(deps),
      config.listen.host,
      config.listen.port,
    );
    log.info('listening', {'host': config.listen.host, 'port': server.port});
    return RunningServer(server.port, () async {
      // ponytail: force close; drain in-flight requests on SIGTERM when it matters.
      await server.close(force: true);
      await db.close();
    });
  } catch (_) {
    await db.close();
    rethrow;
  }
}

/// GET /healthz on the loopback address of `listen`: 0 when it answers 200, else 1.
Future<int> healthcheck(Config config) async {
  final host = switch (config.listen.host) {
    '0.0.0.0' => '127.0.0.1',
    '::' => '::1',
    final h => h,
  };
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client
        .get(host, config.listen.port, '/healthz')
        .timeout(const Duration(seconds: 3));
    final response = await request.close().timeout(const Duration(seconds: 3));
    await response.drain<void>();
    return response.statusCode == 200 ? 0 : 1;
  } catch (_) {
    return 1;
  } finally {
    client.close(force: true);
  }
}
