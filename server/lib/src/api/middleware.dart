// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'app.dart';
import 'errors.dart';

const _headers = {
  'x-content-type-options': 'nosniff',
  'x-frame-options': 'DENY',
  'referrer-policy': 'no-referrer',
  'content-security-policy': "default-src 'none'; frame-ancestors 'none'",
  'cache-control': 'no-store',
};

Middleware securityHeaders() =>
    (inner) =>
        (request) async => (await inner(request)).change(headers: _headers);

/// One line per request; path without query; never headers or bodies.
Middleware requestLog() =>
    (inner) => (request) async {
      final sw = Stopwatch()..start();
      final response = await inner(request);
      final deps = depsOf(request);
      final ip = clientIpOf(request);
      if (deps.config.trustedProxies.isEmpty &&
          !deps.proxyWarned &&
          isLanHost(Uri(host: ip.address))) {
        // Behind a reverse proxy every client would share this address.
        deps.proxyWarned = true;
        deps.log.warn(
          'requests come from ${ip.address} and trusted_proxies is empty: '
          'set it to the reverse proxy address',
        );
      }
      deps.log.request(
        method: request.method,
        path: request.requestedUri.path,
        status: response.statusCode,
        ms: sw.elapsedMilliseconds,
        ip: ip.address,
      );
      return response;
    };

// Routes an old client may still write to, so it can sign in and protect the account.
final _neverTooOld = [
  (
    'POST',
    RegExp(
      r'^/api/v1/(prelogin|login|token/refresh|account/password|events/ssh|events/reveal)$',
    ),
  ),
  ('DELETE', RegExp(r'^/api/v1/devices/[^/]+$')),
];

Middleware clientVersionGate() =>
    (inner) => (request) {
      final String version;
      try {
        version = canonicalVersion(request.headers['x-unfeudal-client'] ?? '');
      } on FormatException {
        throw ApiError(
          ApiErrorCode.invalidRequest,
          'Header X-Unfeudal-Client: X.Y.Z is required.',
        );
      }
      final write = request.method != 'GET' && request.method != 'HEAD';
      final path = request.requestedUri.path;
      final exempt = _neverTooOld.any(
        (e) => e.$1 == request.method && e.$2.hasMatch(path),
      );
      if (write &&
          !exempt &&
          compareVersions(version, depsOf(request).config.minClientVersion) <
              0) {
        throw ApiError(
          ApiErrorCode.conflict,
          'Update Unfeudal to make changes.',
          extra: {'reason': ConflictReason.clientTooOld.wire},
        );
      }
      return inner(request);
    };

class AuthContext {
  const AuthContext(
    this.userId,
    this.deviceId,
    this.isInstanceOwner,
    this.lastSeenAt,
  );

  final String userId;
  final String deviceId;
  final bool isInstanceOwner;

  /// The device's `last_seen_at` as read at authentication.
  final String lastSeenAt;
}

const _authKey = 'unfeudal.auth';

AuthContext authOf(Request request) =>
    request.context[_authKey]! as AuthContext;

ApiError _unauthorized(UnauthorizedReason r) => ApiError(
  ApiErrorCode.unauthorized,
  'Sign in again.',
  extra: {'reason': r.wire},
);

/// Checks the token (prefix, one dot, MAC, JSON, exp), then the user joined
/// with the device. Writes nothing.
Handler requireAuth(Handler inner) => (request) async {
  final deps = depsOf(request);
  final claims = deps.access.verifyHeader(request.headers['authorization']);
  if (claims == null) throw _unauthorized(UnauthorizedReason.invalidToken);
  final rows = await deps.db.query(
    'SELECT u.is_instance_owner, u.disabled, d.revoked_at, d.last_seen_at FROM users u '
    'JOIN devices d ON d.user_id = u.id WHERE u.id = @u AND d.id = @d',
    {'u': claims.userId, 'd': claims.deviceId},
  );
  if (rows.isEmpty ||
      rows.single['disabled'] != 0 ||
      rows.single['revoked_at'] != null) {
    throw _unauthorized(UnauthorizedReason.deviceRevoked);
  }
  return inner(
    request.change(
      context: {
        _authKey: AuthContext(
          claims.userId,
          claims.deviceId,
          rows.single['is_instance_owner'] == 1,
          rows.single['last_seen_at']! as String,
        ),
      },
    ),
  );
};

Middleware requireFeature(Flag flag) =>
    (inner) => (request) {
      if (!depsOf(request).features.enabled(flag)) {
        throw ApiError(
          ApiErrorCode.featureDisabled,
          'This feature is off on this server.',
        );
      }
      return inner(request);
    };
