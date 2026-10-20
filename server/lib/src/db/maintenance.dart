// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';
import 'dart:typed_data';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../auth/tokens.dart';
import '../config/config.dart';
import 'db.dart';

/// A maintenance command the operator asked for cannot run; [message] is shown as is.
class MaintenanceError implements Exception {
  const MaintenanceError(this.message);

  final String message;

  @override
  String toString() => 'maintenance: $message';
}

// Creates the file empty and owner-only before anything secret is written to it.
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
    await file.writeAsBytes(secureBytes(32), flush: true);
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
    {'v': b64(secureBytes(16))},
  );
  return (await db.query("SELECT value FROM meta WHERE key = 'instance_epoch'"))
          .single['value']!
      as String;
}

/// Inserts or replaces one `meta` row.
Future<void> setMeta(Tx tx, String key, String value) => tx.execute(
  'INSERT INTO meta (key, value) VALUES (@k, @v) '
  'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
  {'k': key, 'v': value},
);

/// Clients then see a restored server and run their restore flow.
Future<String> newInstanceEpoch(Db db) async {
  final epoch = b64(secureBytes(16));
  await setMeta(db, 'instance_epoch', epoch);
  return epoch;
}

/// The token to print once, or null: a user exists, a configured token was
/// stored, or a generated one is already pending.
Future<String?> ensureSetupToken(Db db, String? configured) =>
    db.transaction((tx) async {
      final users = await tx.query('SELECT 1 AS one FROM users LIMIT 1');
      if (users.isNotEmpty) return null;
      if (configured != null) {
        await setMeta(
          tx,
          'setup_token_hash',
          hashToken(normalizeSetupToken(configured)),
        );
        return null;
      }
      final pending = await tx.query(
        "SELECT 1 AS one FROM meta WHERE key = 'setup_token_hash'",
      );
      if (pending.isNotEmpty) return null;
      final token = newSetupToken();
      await setMeta(tx, 'setup_token_hash', hashToken(token));
      return token;
    });

/// A consistent SQLite copy through `VACUUM INTO`, owner-only (it holds hashes
/// and bundles); never over an existing file.
Future<void> backupDatabase(Db db, String path) async {
  if (db.engine == DbEngine.postgres) {
    throw const MaintenanceError('use pg_dump');
  }
  if (File(path).existsSync()) {
    throw FileSystemException('backup target exists', path);
  }
  await _createPrivate(path);
  await db.execute('VACUUM INTO @p', {'p': path});
}

/// Daily cleanup. One cutoff for login_attempts: 24 h is the longest window of any key (login_lockout is at most 24 h).
Future<void> runCleanup(Tx tx, DateTime now, Config config) async {
  final t = iso(now);
  await tx.execute(
    'DELETE FROM login_attempts WHERE (locked_until IS NULL OR locked_until <= @t) AND window_start < @w',
    {'t': t, 'w': iso(now.subtract(const Duration(hours: 24)))},
  );
  await tx.execute(
    'DELETE FROM refresh_tokens WHERE expires_at <= @t OR used_at < @u',
    {'t': t, 'u': iso(now.subtract(const Duration(days: 7)))},
  );
  final c = iso(now.subtract(config.inviteTtl));
  await tx.execute(
    'DELETE FROM invites WHERE expires_at < @c OR accepted_at < @c OR revoked_at < @c',
    {'c': c},
  );
}

/// The old flag to 0, then the new one to 1, in one transaction
/// (users_one_instance_owner forbids two owners at any moment).
Future<void> transferOwner(Db db, String email) => db.transaction((tx) async {
  final target = (await tx.query(
    'SELECT id, is_instance_owner, disabled FROM users WHERE email = @e',
    {'e': email},
  )).firstOrNull;
  if (target == null) {
    throw const MaintenanceError('No account with this email.');
  }
  if (target['is_instance_owner'] == 1) return;
  if (target['disabled'] != 0) {
    throw const MaintenanceError('This account is disabled: enable it first.');
  }
  await tx.execute(
    'UPDATE users SET is_instance_owner = 0 WHERE is_instance_owner = 1',
  );
  await tx.execute('UPDATE users SET is_instance_owner = 1 WHERE id = @u', {
    'u': target['id'],
  });
});
