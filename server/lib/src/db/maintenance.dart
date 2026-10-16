// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';
import 'dart:typed_data';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../auth/tokens.dart';
import '../util/random.dart';
import 'db.dart';

/// Creates [path] empty and owner-only before anything secret is written to it.
Future<void> _createPrivate(String path) async {
  await File(path).create(exclusive: true);
  if (Platform.isWindows) return;
  final result = await Process.run('chmod', ['600', path]);
  if (result.exitCode != 0) {
    throw FileSystemException('cannot restrict permissions', path);
  }
}

/// 32 bytes, created `0600` at first start; never stored in the database.
Future<Uint8List> loadServerSecret(String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    await _createPrivate(path);
    await file.writeAsBytes(randomBytes(32), flush: true);
  }
  final secret = await file.readAsBytes();
  if (secret.length != 32) {
    throw FileSystemException('server secret must be 32 bytes', path);
  }
  return secret;
}

Future<String> ensureInstanceEpoch(Db db) async {
  await db.execute(
    "INSERT INTO meta (key, value) VALUES ('instance_epoch', @v) "
    'ON CONFLICT (key) DO NOTHING',
    {'v': b64(randomBytes(16))},
  );
  return (await db.query("SELECT value FROM meta WHERE key = 'instance_epoch'"))
          .single['value']!
      as String;
}

/// Clients then see a restored server and run their restore flow.
Future<String> newInstanceEpoch(Db db) async {
  final epoch = b64(randomBytes(16));
  await db.execute(
    "INSERT INTO meta (key, value) VALUES ('instance_epoch', @v) "
    'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
    {'v': epoch},
  );
  return epoch;
}

/// The token to print once, or null: a user exists, a configured token was
/// stored, or a generated one is already pending.
Future<String?> ensureSetupToken(Db db, String? configured) =>
    db.transaction((tx) async {
      final users = await tx.query('SELECT 1 AS one FROM users LIMIT 1');
      if (users.isNotEmpty) return null;
      if (configured != null) {
        await tx.execute(
          "INSERT INTO meta (key, value) VALUES ('setup_token_hash', @v) "
          'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
          {'v': hashToken(normalizeSetupToken(configured))},
        );
        return null;
      }
      final pending = await tx.query(
        "SELECT 1 AS one FROM meta WHERE key = 'setup_token_hash'",
      );
      if (pending.isNotEmpty) return null;
      final token = newSetupToken();
      await tx.execute(
        "INSERT INTO meta (key, value) VALUES ('setup_token_hash', @v)",
        {'v': hashToken(token)},
      );
      return token;
    });

/// A consistent SQLite copy through `VACUUM INTO`, owner-only (it holds hashes
/// and bundles); never over an existing file.
Future<void> backupDatabase(Db db, String path) async {
  if (db.engine == DbEngine.postgres) throw UnsupportedError('use pg_dump');
  if (File(path).existsSync()) {
    throw FileSystemException('backup target exists', path);
  }
  await _createPrivate(path);
  await db.execute('VACUUM INTO @p', {'p': path});
}
