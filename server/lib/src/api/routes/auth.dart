// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../auth/secret_hash.dart';
import '../../audit/audit_log.dart';
import '../../auth/tokens.dart';
import '../../mail/mailer.dart';
import '../app.dart';
import '../credentials.dart';
import '../errors.dart';
import '../json.dart';
import '../session.dart';
import '../validate.dart';

/// The stored salt and KDF; an unknown email gets a stable fake salt with the
/// default KDF, so the answer never tells whether the account exists.
Future<Response> prelogin(Request request) async {
  final deps = depsOf(request);
  final body = await readJson(request);
  final email = normalizeEmail(body['email']);
  final rows = await deps.db.query(
    'SELECT bundle FROM users WHERE email = @e',
    {'e': email},
  );
  if (rows.isEmpty) {
    return jsonResponse({
      'salt': b64(preloginFakeSalt(deps.serverSecret, email)),
      'kdf': KdfParams.defaults.toJson(),
    });
  }
  final bundle =
      jsonDecode(rows.single['bundle']! as String) as Map<String, Object?>;
  return jsonResponse({'salt': bundle['salt'], 'kdf': bundle['kdf']});
}

Future<Response> login(Request request) async {
  final deps = depsOf(request);
  final body = await readJson(request);
  final email = normalizeEmail(body['email']);
  // Counted even if the rest of the body is malformed.
  await limitCredentials(request, email);
  final authKey = reqKey32(body, 'authKey');
  final device = parseDevice(body['device']);
  final rows = await deps.db.query(
    'SELECT id, is_instance_owner, disabled, bundle, bundle_version, auth_hash '
    'FROM users WHERE email = @e',
    {'e': email},
  );
  final user = rows.firstOrNull;
  final stored =
      user?['auth_hash'] as String? ?? await dummyHash(deps.secretHash);
  // Always exactly one verification, known email or not.
  final ok = await verifySecret(stored, authKey);
  if (user == null || !ok || user['disabled'] != 0) {
    if (user == null) deps.log.info('login refused: unknown account');
    if (user != null && !ok) {
      // own transaction, committed before the 401; an unknown email is never recorded
      await deps.db.transaction(
        (tx) => auditWriter(request, tx, actor: (user: null, device: null))(
          AuditScope.user(user['id']! as String),
          'auth.login_failed',
          const [],
        ),
      );
    }
    throw ApiError(
      ApiErrorCode.unauthorized,
      'Wrong email or master password.',
    );
  }
  final userId = user['id']! as String;
  // The key is right, whatever follows.
  await clearCredentials(request, email);
  final session = await deps.db.transaction((tx) async {
    final max = deps.config.maxDevicesPerUser;
    if (max > 0) {
      final active =
          (await tx.query(
                'SELECT count(*) AS n FROM devices WHERE user_id = @u AND revoked_at IS NULL',
                {'u': userId},
              )).single['n']!
              as int;
      if (active >= max) {
        throw ApiError(
          ApiErrorCode.forbidden,
          'Device limit reached. Revoke a device first.',
        );
      }
    }
    return createSession(
      request,
      tx,
      userId: userId,
      isInstanceOwner: user['is_instance_owner'] == 1,
      bundle: jsonDecode(user['bundle']! as String) as Map<String, Object?>,
      bundleVersion: user['bundle_version']! as int,
      device: device,
    );
  });
  deps.notifier.notify(userId, MailKind.newDevice, {
    'device': device.name,
    'platform': device.platform,
  });
  return jsonResponse(session.toJson());
}

/// A fresh access token and the refresh successor; a replay revokes the device.
Future<Response> refreshToken(Request request) async {
  final deps = depsOf(request);
  final body = await readJson(request);
  final rotated = await deps.refresh.rotate(
    reqString(body, 'refreshToken', max: 200),
    ip: clientIpOf(request).address,
  );
  return jsonResponse(
    TokenPair(
      deps.access.issue(rotated.userId, rotated.deviceId),
      rotated.refreshToken,
    ).toJson(),
  );
}
