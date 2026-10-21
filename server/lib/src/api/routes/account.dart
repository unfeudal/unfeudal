// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../audit/audit_log.dart';
import '../../auth/secret_hash.dart';
import '../../auth/tokens.dart';
import '../../db/db.dart';
import '../../db/deletion.dart';
import '../../mail/mailer.dart';
import '../credentials.dart';
import '../deps.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';
import '../request_audit.dart';
import '../validate.dart';

typedef _User = ({
  String id,
  String email,
  bool disabled,
  Map<String, Object?> bundle,
  int bundleVersion,
  String authHash,
  String? recoveryHash,
});

const _columns =
    'id, email, disabled, bundle, bundle_version, auth_hash, recovery_auth_hash';

_User _parseUser(Map<String, Object?> r) => (
  id: r['id']! as String,
  email: r['email']! as String,
  disabled: r['disabled'] != 0,
  bundle: jsonDecode(r['bundle']! as String) as Map<String, Object?>,
  bundleVersion: r['bundle_version']! as int,
  authHash: r['auth_hash']! as String,
  recoveryHash: r['recovery_auth_hash'] as String?,
);

Future<_User> _userById(Db db, String id) async => _parseUser(
  (await db.query('SELECT $_columns FROM users WHERE id = @id', {
    'id': id,
  })).single,
);

Future<_User?> _userByEmail(Db db, String email) async {
  final rows = await db.query('SELECT $_columns FROM users WHERE email = @e', {
    'e': email,
  });
  return rows.isEmpty ? null : _parseUser(rows.single);
}

int _parseBundleVersion(Map<String, Object?> body) {
  final v = body['bundleVersion'];
  if (v is! int || v < 0) {
    throw ApiError.invalid('bundleVersion: must be an integer >= 0');
  }
  return v;
}

Map<String, Object?> _parseBundle(AppDeps deps, Map<String, Object?> body) =>
    parseBundle(body['bundle'], kdfFloor: deps.kdfFloor);

void _requireVersion(_User user, int version) {
  if (user.bundleVersion != version) throw _stale();
}

ApiError _stale() => ApiError(
  ApiErrorCode.conflict,
  'Your account changed on another device. Try again.',
);

// The rate-limit keys reset as soon as the password is right, as on login:
// the credential check succeeded, whatever follows.
Future<void> _requireCurrentAuthKey(
  Request request,
  _User user,
  Map<String, Object?> body,
) async {
  final current = parseKey32(body, 'currentAuthKey');
  if (!await verifySecret(user.authHash, current)) {
    throw ApiError(ApiErrorCode.forbidden, 'Current master password is wrong.');
  }
  await clearCredentials(request, user.email);
}

// A concurrent change gives a 409, never a silent overwrite.
Future<void> _casBundle(
  Tx tx,
  String userId, {
  required int version,
  required Map<String, Object?> bundle,
  String? authHash,
  String? recoveryHash,
}) async {
  final sets = [
    'bundle = @b',
    'bundle_version = bundle_version + 1',
    if (authHash != null) 'auth_hash = @a',
    if (recoveryHash != null) 'recovery_auth_hash = @r',
  ];
  final n = await tx.execute(
    'UPDATE users SET ${sets.join(', ')} WHERE id = @u AND bundle_version = @v',
    {
      'b': jsonEncode(bundle),
      'u': userId,
      'v': version,
      'a': ?authHash,
      'r': ?recoveryHash,
    },
  );
  if (n == 0) throw _stale();
}

Future<void> _revokeAll(
  Tx tx,
  String userId,
  DateTime now, {
  String? exceptDeviceId,
}) async {
  final rows = await tx.query(
    'SELECT id FROM devices WHERE user_id = @u AND revoked_at IS NULL',
    {'u': userId},
  );
  for (final r in rows) {
    if (r['id'] != exceptDeviceId) {
      await revokeDevice(tx, r['id']! as String, now);
    }
  }
}

/// Replaces the master-password wrap and proof, then revokes every other device.
Future<Response> changePassword(Request request) async {
  final deps = depsOf(request);
  final auth = authOf(request);
  final body = await readJson(request);
  final bundle = _parseBundle(deps, body);
  final authKey = parseKey32(body, 'authKey');
  final version = _parseBundleVersion(body);
  final user = await _userById(deps.db, auth.userId);
  await limitCredentials(request, user.email);
  await _requireCurrentAuthKey(request, user, body);
  requireBundleChangeOnly(user.bundle, bundle, {
    'salt',
    'kdf',
    'wrappedUserKey',
  });
  _requireVersion(user, version);
  final authHash = await hashSecret(authKey, deps.secretHash);
  await deps.db.transaction((tx) async {
    await _casBundle(
      tx,
      user.id,
      version: version,
      bundle: bundle,
      authHash: authHash,
    );
    await _revokeAll(
      tx,
      user.id,
      deps.clock.now(),
      exceptDeviceId: auth.deviceId,
    );
    await auditWriter(request, tx)(
      AuditScope.user(auth.userId),
      'account.password_changed',
      const [],
    );
  });
  deps.notifier.notify(auth.userId, MailKind.passwordChanged);
  return noContent();
}

// The same 401 for every failure, and a hash is verified even for an unknown
// email, so neither the response nor its timing tells which accounts exist.
Future<_User> _proveRecovery(Request request, Map<String, Object?> body) async {
  final deps = depsOf(request);
  final email = normalizeEmail(body['email']);
  await limitCredentials(request, email);
  final key = parseKey32(body, 'recoveryAuthKey');
  final user = await _userByEmail(deps.db, email);
  final stored = user?.recoveryHash ?? await dummyHash(deps.secretHash);
  final ok = await verifySecret(stored, key);
  if (user == null || user.recoveryHash == null || !ok || user.disabled) {
    throw ApiError(
      ApiErrorCode.unauthorized,
      'Unknown email or invalid recovery key.',
    );
  }
  return user;
}

/// Proves the recovery key and returns the stored bundle.
Future<Response> recoverStart(Request request) async {
  final body = await readJson(request);
  final user = await _proveRecovery(request, body);
  await clearCredentials(request, user.email);
  return jsonResponse({
    'bundle': user.bundle,
    'bundleVersion': user.bundleVersion,
  });
}

/// Resets master password and recovery key; revokes every device, opens no session.
Future<Response> recover(Request request) async {
  final deps = depsOf(request);
  final body = await readJson(request);
  final user = await _proveRecovery(request, body);
  final bundle = _parseBundle(deps, body);
  requireBundleChangeOnly(user.bundle, bundle, {
    'salt',
    'kdf',
    'wrappedUserKey',
    'wrappedUserKeyByRecovery',
  });
  final authKey = parseKey32(body, 'authKey');
  final newRecoveryAuthKey = parseKey32(body, 'newRecoveryAuthKey');
  _requireVersion(user, _parseBundleVersion(body));
  final authHash = await hashSecret(authKey, deps.secretHash);
  final recoveryHash = await hashSecret(newRecoveryAuthKey, deps.secretHash);
  await deps.db.transaction((tx) async {
    await _casBundle(
      tx,
      user.id,
      version: user.bundleVersion,
      bundle: bundle,
      authHash: authHash,
      recoveryHash: recoveryHash,
    );
    await _revokeAll(tx, user.id, deps.clock.now());
    await auditWriter(request, tx, actor: (user: user.id, device: null))(
      AuditScope.user(user.id),
      'account.recovery_used',
      const [],
    );
  });
  deps.notifier.notify(user.id, MailKind.recoveryUsed);
  // Only after every check passed.
  await clearCredentials(request, user.email);
  return noContent();
}

/// Replaces the recovery key; only wrappedUserKeyByRecovery and the recovery proof change.
Future<Response> recoveryKit(Request request) async {
  final deps = depsOf(request);
  final auth = authOf(request);
  final body = await readJson(request);
  final bundle = _parseBundle(deps, body);
  final recoveryAuthKey = parseKey32(body, 'recoveryAuthKey');
  final version = _parseBundleVersion(body);
  final user = await _userById(deps.db, auth.userId);
  await limitCredentials(request, user.email);
  await _requireCurrentAuthKey(request, user, body);
  requireBundleChangeOnly(user.bundle, bundle, {'wrappedUserKeyByRecovery'});
  _requireVersion(user, version);
  final recoveryHash = await hashSecret(recoveryAuthKey, deps.secretHash);
  await deps.db.transaction((tx) async {
    await _casBundle(
      tx,
      user.id,
      version: version,
      bundle: bundle,
      recoveryHash: recoveryHash,
    );
    await auditWriter(request, tx)(
      AuditScope.user(auth.userId),
      'account.recovery_kit_changed',
      const [],
    );
  });
  return noContent();
}

/// The language of the mails this account receives.
Future<Response> setLocale(Request request) async {
  final deps = depsOf(request);
  final body = await readJson(request);
  final locale = parseLocale(body['locale']);
  await deps.db.execute('UPDATE users SET locale = @l WHERE id = @u', {
    'l': locale,
    'u': authOf(request).userId,
  });
  return noContent();
}

Future<Response> deleteAccount(Request request) async {
  final deps = depsOf(request);
  final auth = authOf(request);
  if (auth.isInstanceOwner) {
    throw ApiError(
      ApiErrorCode.forbidden,
      'The Instance Owner cannot be deleted.',
    );
  }
  final body = await readJson(request);
  final user = await _userById(deps.db, auth.userId);
  // Counted before the key is checked, so wrong guesses are rate limited.
  await limitCredentials(request, user.email);
  await _requireCurrentAuthKey(request, user, body);
  // deleteUser refuses the last owner of an organization with a 409.
  await deps.db.transaction(
    (tx) => deleteUser(tx, auth.userId, audit: auditWriter(request, tx)),
  );
  return noContent();
}
