// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:unfeudal_server/src/config/config.dart';
import 'package:unfeudal_server/src/db/db.dart';
import 'package:unfeudal_server/src/db/maintenance.dart';
import 'package:unfeudal_server/src/db/migrate.dart';
import 'package:unfeudal_server/src/run_server.dart';

const _usage =
    'usage: unfeudal-server [healthcheck | backup <path> | new-epoch]';

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
      try {
        await runServer(config);
      } catch (e) {
        stderr.writeln('cannot start: $e');
        exit(1);
      }
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
