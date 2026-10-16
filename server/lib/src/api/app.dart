// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../auth/rate_limit.dart';
import '../auth/secret_hash.dart';
import '../auth/tokens.dart';
import '../config/config.dart';
import '../config/features.dart';
import '../db/db.dart';
import '../db/maintenance.dart';
import '../log/logger.dart';
import '../util/clock.dart';
import 'errors.dart';
import 'middleware.dart';
import 'routes/auth.dart';
import 'routes/devices.dart';
import 'routes/health.dart';
import 'routes/info.dart';
import 'routes/setup.dart';

/// Everything a request handler needs, built once at start.
class AppDeps {
  AppDeps._({
    required this.config,
    required this.db,
    required this.clock,
    required this.log,
    required this.serverSecret,
    required this.instanceEpoch,
    required this.access,
    required this.refresh,
    required this.limiter,
    required this.secretHash,
    required this.allowTestingKdf,
  });

  static Future<AppDeps> create(
    Config config,
    Db db, {
    Clock clock = const SystemClock(),
    Logger? log,
    SecretHashParams secretHash = SecretHashParams.server,
    bool allowTestingKdf = false,
  }) async {
    final serverSecret = await loadServerSecret(config.secretFile);
    return AppDeps._(
      config: config,
      db: db,
      clock: clock,
      log: log ?? Logger(config.logLevel, stdout.writeln),
      serverSecret: serverSecret,
      instanceEpoch: await ensureInstanceEpoch(db),
      access: AccessTokens(serverSecret, clock, config.accessTokenTtl),
      refresh: RefreshTokens(db, clock, config.refreshTokenTtl, serverSecret),
      limiter: RateLimiter(db, clock, config),
      secretHash: secretHash,
      allowTestingKdf: allowTestingKdf,
    );
  }

  final Config config;
  final Db db;
  final Clock clock;
  final Logger log;
  final Uint8List serverSecret;

  /// Cached for `/api/info`.
  final String instanceEpoch;
  final AccessTokens access;
  final RefreshTokens refresh;
  final RateLimiter limiter;
  final SecretHashParams secretHash;

  /// Tests only.
  final bool allowTestingKdf;

  /// One trusted_proxies warning per process.
  bool proxyWarned = false;

  Features get features => config.features;
}

const _depsKey = 'unfeudal.deps';

Middleware withDeps(AppDeps deps) =>
    (inner) =>
        (request) => inner(request.change(context: {_depsKey: deps}));

AppDeps depsOf(Request request) => request.context[_depsKey]! as AppDeps;

Never _notFound(Request _) =>
    throw ApiError(ApiErrorCode.notFound, 'Not found.');

/// withDeps → requestLog → securityHeaders → errorMapper → routes.
Handler buildHandler(AppDeps deps) {
  final api = Router(notFoundHandler: _notFound)
    ..post('/setup', setup)
    ..post('/prelogin', prelogin)
    ..post('/login', login)
    ..get('/devices', requireAuth(listDevices))
    ..delete(
      '/devices/<id>',
      (Request r, String id) => requireAuth((r) => deleteDevice(r, id))(r),
    );
  final root = Router(notFoundHandler: _notFound)
    ..get('/healthz', healthz)
    ..get('/api/info', info)
    ..mount(
      '/api/v1/',
      const Pipeline().addMiddleware(clientVersionGate()).addHandler(api.call),
    );
  return const Pipeline()
      .addMiddleware(withDeps(deps))
      .addMiddleware(requestLog())
      .addMiddleware(securityHeaders())
      .addMiddleware(errorMapper())
      .addHandler(root.call);
}
