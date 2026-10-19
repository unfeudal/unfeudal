// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../auth/secret_hash.dart';
import '../../audit/audit_log.dart';
import '../../auth/tokens.dart';
import '../../db/db.dart';
import '../../db/deletion.dart';
import '../../mail/mailer.dart';
import '../app.dart';
import '../credentials.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';
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

_User _user(Map<String, Object?> r) => (
  id: r['id']! as String,
  email: r['email']! as String,
  disabled: r['disabled'] != 0,
  bundle: jsonDecode(r['bundle']! as String) as Map<String, Object?>,
  bundleVersion: r['bundle_version']! as int,
  authHash: r['auth_hash']! as String,
  recoveryHash: r['recovery_auth_hash'] as String?,
);

Future<_User> _userById(Db db, String id) async => _user(
  (await db.query('SELECT $_columns FROM users WHERE id = @id', {
    'id': id,
  })).single,
);

Future<_User?> _userByEmail(Db db, String email) async {
  final rows = await db.query('SELECT $_columns FROM users WHERE email = @e', {
    'e': email,
  });
  return rows.isEmpty ? null : _user(rows.single);
}

int _bundleVersion(Map<String, Object?> body) {
  final v = body['bundleVersion'];
  if (v is! int || v < 0) {
    throw ApiError(
      ApiErrorCode.invalidRequest,
      'bundleVersion: must be an integer >= 0',
    );
  }
  return v;
}

/// The request's bundle as a map, after its model and KDF checks.
Map<String, Object?> _bundle(AppDeps deps, Map<String, Object?> body) {
  parseBundle(body['bundle'], allowTestingKdf: deps.allowTestingKdf);
  return body['bundle']! as Map<String, Object?>;
}

void _requireVersion(_User user, int version) {
  if (user.bundleVersion != version) throw _stale();
}

ApiError _stale() => ApiError(
  ApiErrorCode.conflict,
  'Your account changed on another device. Try again.',
);

/// Proof by the current master password. The acct keys reset as soon as it
/// is right, as on login: the credential check succeeded, whatever follows.
Future<void> _requireCurrentAuthKey(
  Request request,
  _User user,
  Map<String, Object?> body,
) async {
  final current = reqKey32(body, 'currentAuthKey');
  if (!await verifySecret(user.authHash, current)) {
    throw ApiError(ApiErrorCode.forbidden, 'Current master password is wrong.');
  }
  await clearCredentials(request, user.email);
}

/// Compare-and-swap on bundle_version: a concurrent change → 409, never a silent overwrite.
Future<void> _casBundle(
  Tx tx,
  String userId,
  int version,
  Map<String, Object?> bundle, {
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
  final bundle = _bundle(deps, body);
  final authKey = reqKey32(body, 'authKey');
  final version = _bundleVersion(body);
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
    await _casBundle(tx, user.id, version, bundle, authHash: authHash);
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

/// Checks 1–4 of recover/start: one recovery proof, the same 401 for every failure.
Future<_User> _proveRecovery(Request request, Map<String, Object?> body) async {
  final deps = depsOf(request);
  final email = normalizeEmail(body['email']);
  await limitCredentials(request, email);
  final key = reqKey32(body, 'recoveryAuthKey');
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
  final bundle = _bundle(deps, body);
  requireBundleChangeOnly(user.bundle, bundle, {
    'salt',
    'kdf',
    'wrappedUserKey',
    'wrappedUserKeyByRecovery',
  });
  final authKey = reqKey32(body, 'authKey');
  final newRecoveryAuthKey = reqKey32(body, 'newRecoveryAuthKey');
  _requireVersion(user, _bundleVersion(body));
  final authHash = await hashSecret(authKey, deps.secretHash);
  final recoveryHash = await hashSecret(newRecoveryAuthKey, deps.secretHash);
  await deps.db.transaction((tx) async {
    await _casBundle(
      tx,
      user.id,
      user.bundleVersion,
      bundle,
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
  final bundle = _bundle(deps, body);
  final recoveryAuthKey = reqKey32(body, 'recoveryAuthKey');
  final version = _bundleVersion(body);
  final user = await _userById(deps.db, auth.userId);
  await limitCredentials(request, user.email);
  await _requireCurrentAuthKey(request, user, body);
  requireBundleChangeOnly(user.bundle, bundle, {'wrappedUserKeyByRecovery'});
  _requireVersion(user, version);
  final recoveryHash = await hashSecret(recoveryAuthKey, deps.secretHash);
  await deps.db.transaction((tx) async {
    await _casBundle(tx, user.id, version, bundle, recoveryHash: recoveryHash);
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
  final auth = authOf(request); // 1. requireAuth wraps this handler
  if (auth.isInstanceOwner) {
    throw ApiError(
      ApiErrorCode.forbidden,
      'The Instance Owner cannot be deleted.',
    ); // 2.
  }
  final body = await readJson(request); // 3.
  final user = (await deps.db.query(
    'SELECT email, auth_hash FROM users WHERE id = @u',
    {'u': auth.userId},
  )).single;
  final email = user['email']! as String;
  await limitCredentials(request, email); // 4. counted before the key is read
  final current = reqKey32(body, 'currentAuthKey');
  if (!await verifySecret(user['auth_hash']! as String, current)) {
    throw ApiError(ApiErrorCode.forbidden, 'Current master password is wrong.');
  }
  await clearCredentials(
    request,
    email,
  ); // the key was right, whatever refuses next
  await deps.db.transaction(
    (tx) => deleteUser(
      tx,
      auth.userId,
      actor: auth.userId,
      audit: auditWriter(request, tx),
    ),
  ); // 5. last owner → 409 inside
  return noContent();
}
