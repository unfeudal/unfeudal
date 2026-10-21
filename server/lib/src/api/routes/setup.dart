// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../audit/audit_log.dart';
import '../../auth/rate_limit.dart';
import '../../auth/secret_hash.dart';
import '../../auth/tokens.dart';
import '../../db/db.dart';
import '../../mail/templates.dart';
import '../../net/client_ip.dart';
import '../deps.dart';
import '../errors.dart';
import '../json.dart';
import '../request_audit.dart';
import '../session.dart';
import '../validate.dart';

ApiError _setupDone() =>
    ApiError(ApiErrorCode.setupDone, 'This server is already set up.');

Future<bool> _hasUser(Db db) async =>
    (await db.query('SELECT id FROM users LIMIT 1')).isNotEmpty;

Future<void> _requireSetupToken(Db db, String tokenHash) async {
  final stored = await db.query(
    "SELECT value FROM meta WHERE key = 'setup_token_hash'",
  );
  if (stored.isEmpty ||
      !constantTimeEquals(
        utf8.encode(stored.single['value']! as String),
        utf8.encode(tokenHash),
      )) {
    // A concurrent setup may have committed since the first check.
    if (await _hasUser(db)) throw _setupDone();
    // No reason on setup: one message for every failure.
    throw ApiError(ApiErrorCode.unauthorized, 'Invalid setup token.');
  }
}

/// Creates the Instance Owner with the one-time setup token, and its first session.
Future<Response> setup(Request request) async {
  final deps = depsOf(request);
  final net = netOf(clientIpOf(request));
  // Never refunded: setup happens once.
  await deps.limiter.hit([ipKey(net)]);
  final body = await readJson(request);
  final token = normalizeSetupToken(
    parseRequiredString(body, 'token', max: 200),
  );
  final email = normalizeEmail(body['email']);
  final bundle = parseBundle(body['bundle'], kdfFloor: deps.kdfFloor);
  final authKey = parseKey32(body, 'authKey');
  final recoveryAuthKey = parseKey32(body, 'recoveryAuthKey');
  final device = parseDevice(body['device']);
  final locale = body.containsKey('locale')
      ? parseLocale(body['locale'])
      : defaultLocale;
  if (await _hasUser(deps.db)) throw _setupDone();
  final tokenHash = hashToken(token);
  await _requireSetupToken(deps.db, tokenHash);
  // Argon2 before the transaction.
  final authHash = await hashSecret(authKey, deps.secretHash);
  final recoveryHash = await hashSecret(recoveryAuthKey, deps.secretHash);
  final session = await deps.db.transaction((tx) async {
    // The DELETE decides a race between concurrent setups.
    final claimed = await tx.execute(
      "DELETE FROM meta WHERE key = 'setup_token_hash' AND value = @h",
      {'h': tokenHash},
    );
    if (claimed == 0) throw _setupDone();
    final userId = await insertUser(
      tx,
      deps,
      email: email,
      bundle: bundle,
      authHash: authHash,
      recoveryHash: recoveryHash,
      locale: locale,
      isInstanceOwner: true,
    );
    final session = await createSession(
      request,
      tx,
      userId: userId,
      isInstanceOwner: true,
      bundle: bundle,
      bundleVersion: 0,
      device: device,
    );
    // after the session exists: its device is the actor
    await auditWriter(
      request,
      tx,
      actor: (user: userId, device: session.deviceId),
    )(AuditScope.instance, 'setup.completed', [userId]);
    return session;
  });
  return jsonResponse(session.toJson(), status: 201);
}
