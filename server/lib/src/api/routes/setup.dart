// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:cryptography/helpers.dart' show constantTimeBytesEquality;
import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../auth/rate_limit.dart';
import '../../auth/secret_hash.dart';
import '../../auth/tokens.dart';
import '../../net/client_ip.dart';
import '../app.dart';
import '../errors.dart';
import '../json.dart';
import '../session.dart';
import '../validate.dart';

ApiError _setupDone() =>
    ApiError(ApiErrorCode.setupDone, 'This server is already set up.');

/// Creates the Instance Owner with the one-time setup token, and its first session.
Future<Response> setup(Request request) async {
  final deps = depsOf(request);
  final net = netOf(clientIp(request, deps.config.trustedProxies));
  // Never refunded: setup happens once.
  await deps.limiter.hit([ipKey(net)]);
  final body = await readJson(request);
  final token = normalizeSetupToken(reqString(body, 'token', max: 200));
  final email = normalizeEmail(body['email']);
  final bundle = body['bundle'];
  parseBundle(bundle, allowTestingKdf: deps.allowTestingKdf);
  final authKey = reqKey32(body, 'authKey');
  final recoveryAuthKey = reqKey32(body, 'recoveryAuthKey');
  final device = parseDevice(body['device']);
  final locale = body.containsKey('locale')
      ? parseLocale(body['locale'])
      : 'en';
  Future<bool> hasUser() async =>
      (await deps.db.query('SELECT id FROM users LIMIT 1')).isNotEmpty;
  if (await hasUser()) throw _setupDone();
  final h = hashToken(token);
  final stored = await deps.db.query(
    "SELECT value FROM meta WHERE key = 'setup_token_hash'",
  );
  if (stored.isEmpty ||
      !constantTimeBytesEquality.equals(
        utf8.encode(stored.single['value']! as String),
        utf8.encode(h),
      )) {
    // A concurrent setup may have committed since the first check.
    if (await hasUser()) throw _setupDone();
    // No reason on setup: one message for every failure.
    throw ApiError(ApiErrorCode.unauthorized, 'Invalid setup token.');
  }
  // Argon2 before the transaction.
  final authHash = await hashSecret(authKey, deps.secretHash);
  final recoveryHash = await hashSecret(recoveryAuthKey, deps.secretHash);
  final session = await deps.db.transaction((tx) async {
    // The DELETE decides a race between concurrent setups.
    final claimed = await tx.execute(
      "DELETE FROM meta WHERE key = 'setup_token_hash' AND value = @h",
      {'h': h},
    );
    if (claimed == 0) throw _setupDone();
    final userId = newId();
    await tx.execute(
      'INSERT INTO users (id, email, is_instance_owner, bundle, bundle_version, auth_hash, '
      'recovery_auth_hash, created_at, locale) '
      'VALUES (@id, @email, 1, @bundle, 0, @auth, @recovery, @now, @locale)',
      {
        'id': userId,
        'email': email,
        'bundle': jsonEncode(bundle),
        'auth': authHash,
        'recovery': recoveryHash,
        'now': iso(deps.clock.now()),
        'locale': locale,
      },
    );
    final session = await createSession(
      deps,
      tx,
      userId: userId,
      isInstanceOwner: true,
      bundle: bundle! as Map<String, Object?>,
      bundleVersion: 0,
      device: device,
    );
    // Audit hook: setup.completed (instance), then device.added (user), after the session exists.
    return session;
  });
  return jsonResponse(session.toJson(), status: 201);
}
