// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:io';

import 'package:unfeudal_server/src/config/config.dart';
import 'package:unfeudal_server/src/db/maintenance.dart';
import 'package:unfeudal_server/src/db/migrate.dart';
import 'package:unfeudal_server/src/db/open_db.dart';
import 'package:unfeudal_server/src/mail/mailer.dart';
import 'package:unfeudal_server/src/mail/smtp_mailer.dart';
import 'package:unfeudal_server/src/run_server.dart';
import 'package:unfeudal_server/src/util/email.dart';

const _usage =
    'usage: unfeudal-server [healthcheck | backup <path> | new-epoch | transfer-owner <email>]';

Future<void> main(List<String> args) async {
  final Config config;
  try {
    config = Config.load(Platform.environment, yamlText: _configFile());
  } on ConfigError catch (e) {
    stderr.writeln(e);
    exit(2);
  }
  switch (args) {
    case []:
      exit(await _serve(config));
    case ['healthcheck']:
      exit(await healthcheck(config));
    case ['backup', final path]:
      exit(await _backup(config, path));
    case ['new-epoch']:
      exit(await _newEpoch(config));
    case ['transfer-owner', final email]:
      exit(await _transferOwner(config, canonicalEmail(email)));
    default:
      stderr.writeln(_usage);
      exit(64);
  }
}

// Returns the YAML text of `UNFEUDAL_CONFIG_FILE`, or null when unset.
String? _configFile() {
  final path = Platform.environment['UNFEUDAL_CONFIG_FILE'];
  if (path == null) return null;
  try {
    return File(path).readAsStringSync();
  } on FileSystemException {
    throw ConfigError('UNFEUDAL_CONFIG_FILE', 'cannot read the file');
  }
}

Future<int> _serve(Config config) async {
  final RunningServer running;
  try {
    running = await runServer(
      config,
      mailer: config.smtp == null
          ? const NoMailer()
          : SmtpMailer(config.smtp!, timezone: config.timezone),
    );
  } on Object catch (e) {
    // Any startup failure ends the process with a message instead of a stack trace.
    stderr.writeln('cannot start: $e');
    return 1;
  }
  final stop = Completer<void>();
  for (final signal in [
    ProcessSignal.sigint,
    // SIGTERM cannot be watched on Windows.
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ]) {
    signal.watch().listen((_) {
      if (!stop.isCompleted) stop.complete();
    });
  }
  await stop.future;
  await running.close();
  return 0;
}

Future<int> _backup(Config config, String path) async {
  final db = await openDb(config.databaseUrl);
  try {
    await backupDatabase(db, path);
    stdout.writeln(
      'Backup written to $path. Keep secret_file with it, and run new-epoch after a restore.',
    );
    return 0;
  } on MaintenanceError catch (e) {
    stderr.writeln(e.message);
    return 1;
  } on FileSystemException catch (e) {
    stderr.writeln('backup failed: ${e.message}');
    return 1;
  } finally {
    await db.close();
  }
}

Future<int> _newEpoch(Config config) async {
  final db = await openDb(config.databaseUrl);
  try {
    await migrate(db);
    stdout.writeln(await newInstanceEpoch(db));
    return 0;
  } finally {
    await db.close();
  }
}

Future<int> _transferOwner(Config config, String email) async {
  final db = await openDb(config.databaseUrl);
  try {
    await migrate(db);
    await transferOwner(db, email);
    stdout.writeln('Instance Owner is now $email.');
    return 0;
  } on MaintenanceError catch (e) {
    stderr.writeln(e.message);
    return 1;
  } finally {
    await db.close();
  }
}
