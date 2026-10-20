// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'api/app.dart';
import 'audit/retention.dart';
import 'config/config.dart';
import 'db/db.dart';
import 'db/maintenance.dart';
import 'db/migrate.dart';
import 'db/postgres_db.dart';
import 'log/logger.dart';
import 'mail/mailer.dart';

class RunningServer {
  RunningServer(this.port, this._close);

  final int port;
  final Future<void> Function(Duration drain) _close;

  /// Stops accepting, lets open requests and queued mails finish within [drain], closes the database.
  Future<void> close({Duration drain = const Duration(seconds: 8)}) =>
      _close(drain);
}

/// Opens and migrates the database (a newer schema refuses to start), prints
/// the setup token once, then serves.
Future<RunningServer> runServer(
  Config config, {
  Logger? log,
  Mailer mailer = const NoMailer(),
}) async {
  log ??= Logger(config.logLevel, stdout.writeln);
  final db = await openDb(config.databaseUrl);
  try {
    await migrate(db);
    if (db is PostgresDb && !await db.collationIsC()) {
      log.warn(
        "database collation is not C: create it with TEMPLATE template0 LC_COLLATE 'C' LC_CTYPE 'C'",
      );
    }
    final deps = await AppDeps.create(config, db, log: log, mailer: mailer);
    final token = await ensureSetupToken(db, config.setupToken);
    // Printed once, raw: redaction would hide it.
    if (token != null) log.sink('Setup token: ${groupBy4(token)}');
    final handler = buildHandler(deps);
    final server = await HttpServer.bind(
      config.listen.host,
      config.listen.port,
    );
    var inFlight = 0;
    Completer<void>? idle;
    server.listen((req) {
      inFlight++; // counted until the response is written, not only until the handler returns
      shelf_io.handleRequest(req, handler).whenComplete(() {
        if (--inFlight == 0 && idle != null && !idle!.isCompleted) {
          idle!.complete();
        }
      });
    });
    log.info('listening', {'host': config.listen.host, 'port': server.port});
    final retention = startRetentionTimer(deps);
    return RunningServer(server.port, (Duration drain) async {
      final deadline = DateTime.now().add(drain);
      // Stops accepting; open requests keep their connection.
      unawaited(server.close());
      if (inFlight > 0) {
        await (idle = Completer<void>()).future.timeout(
          drain,
          onTimeout: () {},
        );
      }
      final left = deadline.difference(DateTime.now());
      await deps.notifier.drain(left.isNegative ? Duration.zero : left);
      await server.close(force: true);
      retention.cancel();
      await db.close();
    });
    // Any startup failure closes the database before propagating.
  } on Object catch (_) {
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
    // Any failure to reach the server means unhealthy.
  } on Object catch (_) {
    return 1;
  } finally {
    client.close(force: true);
  }
}
