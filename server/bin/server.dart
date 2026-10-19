// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:io';

import 'package:unfeudal_server/src/config/config.dart';
import 'package:unfeudal_server/src/db/db.dart';
import 'package:unfeudal_server/src/db/maintenance.dart';
import 'package:unfeudal_server/src/db/migrate.dart';
import 'package:unfeudal_server/src/mail/mailer.dart';
import 'package:unfeudal_server/src/mail/smtp_mailer.dart';
import 'package:unfeudal_server/src/run_server.dart';

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
      final RunningServer running;
      try {
        running = await runServer(
          config,
          mailer: config.smtp == null
              ? const NoMailer()
              : SmtpMailer(config.smtp!, timezone: config.timezone),
        );
      } catch (e) {
        stderr.writeln('cannot start: $e');
        exit(1);
      }
      // SIGTERM cannot be watched on Windows.
      final stop = Completer<void>();
      for (final signal in [
        ProcessSignal.sigint,
        if (!Platform.isWindows) ProcessSignal.sigterm,
      ]) {
        signal.watch().listen((_) {
          if (!stop.isCompleted) stop.complete();
        });
      }
      await stop.future;
      await running.close();
      exit(0);
    case ['healthcheck']:
      exit(await healthcheck(config));
    case ['backup', final path]:
      exit(await _backup(config, path));
    case ['new-epoch']:
      final db = await openDb(config.databaseUrl);
      try {
        await migrate(db);
        stdout.writeln(await newInstanceEpoch(db));
      } finally {
        await db.close();
      }
      exit(0);
    case ['transfer-owner', final email]:
      exit(await _transferOwner(config, email));
    default:
      stderr.writeln(_usage);
      exit(64);
  }
}

/// The YAML text of `UNFEUDAL_CONFIG_FILE`, or null when unset.
String? _configFile() {
  final path = Platform.environment['UNFEUDAL_CONFIG_FILE'];
  if (path == null) return null;
  try {
    return File(path).readAsStringSync();
  } on FileSystemException {
    throw ConfigError('UNFEUDAL_CONFIG_FILE', 'cannot read the file');
  }
}

Future<int> _backup(Config config, String path) async {
  final db = await openDb(config.databaseUrl);
  try {
    await backupDatabase(db, path);
    stdout.writeln(
      'Backup written to $path. Keep secret_file with it, and run new-epoch after a restore.',
    );
    return 0;
  } on UnsupportedError {
    stderr.writeln('use pg_dump');
    return 1;
  } on FileSystemException catch (e) {
    stderr.writeln('backup failed: ${e.message}');
    return 1;
  } finally {
    await db.close();
  }
}

Future<int> _transferOwner(Config config, String email) async {
  final db = await openDb(config.databaseUrl);
  try {
    await migrate(db);
    await transferOwner(db, email);
    stdout.writeln('Instance Owner is now ${email.trim().toLowerCase()}.');
    return 0;
  } on StateError catch (e) {
    stderr.writeln(e.message);
    return 1;
  } finally {
    await db.close();
  }
}
