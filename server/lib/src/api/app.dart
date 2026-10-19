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
import '../mail/mailer.dart';
import '../util/clock.dart';
import 'errors.dart';
import 'middleware.dart';
import 'routes/account.dart';
import 'routes/auth.dart';
import 'routes/devices.dart';
import 'routes/health.dart';
import 'routes/info.dart';
import 'routes/items.dart';
import 'routes/orgs.dart';
import 'routes/setup.dart';
import 'routes/sync.dart';

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
    required this.mailer,
  });

  static Future<AppDeps> create(
    Config config,
    Db db, {
    Clock clock = const SystemClock(),
    Logger? log,
    SecretHashParams secretHash = SecretHashParams.server,
    bool allowTestingKdf = false,
    Mailer mailer = const NoMailer(),
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
      mailer: mailer,
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
  final Mailer mailer;

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

/// An org route: signed in, then the `orgs` flag.
Handler _org(Handler inner) => requireAuth(requireFeature(Flag.orgs)(inner));

/// withDeps → requestLog → securityHeaders → errorMapper → routes.
Handler buildHandler(AppDeps deps) {
  final api = Router(notFoundHandler: _notFound)
    ..post('/setup', setup)
    ..post('/prelogin', prelogin)
    ..post('/login', login)
    ..post('/token/refresh', refreshToken)
    ..post('/account/password', requireAuth(changePassword))
    ..post(
      '/account/recover/start',
      requireFeature(Flag.recoveryKit)(recoverStart),
    )
    ..post('/account/recover', requireFeature(Flag.recoveryKit)(recover))
    ..post(
      '/account/recovery-kit',
      requireAuth(requireFeature(Flag.recoveryKit)(recoveryKit)),
    )
    ..get('/devices', requireAuth(listDevices))
    ..delete(
      '/devices/<id>',
      (Request r, String id) => requireAuth((r) => deleteDevice(r, id))(r),
    )
    ..put(
      '/items/<id>',
      (Request r, String id) => requireAuth((r) => putItem(r, id))(r),
    )
    ..get('/sync', requireAuth(sync))
    ..post('/orgs', _org(createOrg))
    ..put(
      '/orgs/<org>',
      (Request r, String org) => _org((r) => updateOrg(r, org))(r),
    )
    ..delete(
      '/orgs/<org>',
      (Request r, String org) => _org((r) => deleteOrgRoute(r, org))(r),
    )
    ..put(
      '/orgs/<org>/members/<user>',
      (Request r, String org, String user) =>
          _org((r) => setRole(r, org, user))(r),
    )
    ..delete(
      '/orgs/<org>/members/<user>',
      (Request r, String org, String user) =>
          _org((r) => removeMemberRoute(r, org, user))(r),
    )
    ..post(
      '/orgs/<org>/members/<user>/confirm',
      (Request r, String org, String user) =>
          _org((r) => confirmMember(r, org, user))(r),
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
