// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../audit/audit_log.dart';
import '../auth/rate_limit.dart';
import '../auth/secret_hash.dart';
import '../auth/tokens.dart';
import '../config/config.dart';
import '../config/features.dart';
import '../db/db.dart';
import '../db/maintenance.dart';
import '../log/logger.dart';
import '../mail/mailer.dart';
import '../mail/notifier.dart';
import '../net/client_ip.dart';
import '../util/clock.dart';

/// Everything a request handler needs, built once at start.
class AppDeps {
  AppDeps._({
    required this.config,
    required this.db,
    required this.clock,
    required this.log,
    required this.serverSecret,
    required this.instanceEpoch,
    required this.audit,
    required this.access,
    required this.refresh,
    required this.limiter,
    required this.secretHash,
    required this.kdfFloor,
    required this.mailer,
  });

  static Future<AppDeps> create(
    Config config,
    Db db, {
    Clock clock = const SystemClock(),
    required Logger log,
    SecretHashParams secretHash = SecretHashParams.server,
    KdfParams kdfFloor = KdfParams.defaults,
    Mailer mailer = const NoMailer(),
  }) async {
    final serverSecret = await loadServerSecret(config.secretFile);
    final audit = AuditLog(clock, config.features, serverSecret);
    final deps = AppDeps._(
      config: config,
      db: db,
      clock: clock,
      log: log,
      serverSecret: serverSecret,
      instanceEpoch: await ensureInstanceEpoch(db),
      audit: audit,
      access: AccessTokens(serverSecret, clock, config.accessTokenTtl),
      refresh: RefreshTokens(
        db,
        clock,
        config.refreshTokenTtl,
        serverSecret,
        audit: audit,
      ),
      limiter: RateLimiter(db, clock, config),
      secretHash: secretHash,
      kdfFloor: kdfFloor,
      mailer: mailer,
    );
    deps.limiter.onLockout = deps.notifier.lockout;
    return deps;
  }

  final Config config;
  final Db db;
  final Clock clock;
  final Logger log;
  final Uint8List serverSecret;

  /// Cached for `/api/info`.
  final String instanceEpoch;
  final AuditLog audit;
  final AccessTokens access;
  final RefreshTokens refresh;
  final RateLimiter limiter;
  final SecretHashParams secretHash;
  final Mailer mailer;
  late final SecurityNotifier notifier = SecurityNotifier(
    config: config,
    db: db,
    clock: clock,
    mailer: mailer,
    limiter: limiter,
    log: log,
  );

  /// The weakest bundle KDF accepted; lowered by tests only.
  final KdfParams kdfFloor;

  /// One trusted_proxies warning per process.
  bool proxyWarned = false;

  Features get features => config.features;
}

const _depsKey = 'unfeudal.deps';

Middleware withDeps(AppDeps deps) =>
    (inner) =>
        (request) => inner(request.change(context: {_depsKey: deps}));

AppDeps depsOf(Request request) => request.context[_depsKey]! as AppDeps;

InternetAddress clientIpOf(Request request) =>
    clientIp(request, depsOf(request).config.trustedProxies);
