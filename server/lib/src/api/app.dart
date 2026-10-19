// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
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
import '../util/clock.dart';
import 'errors.dart';
import 'middleware.dart';
import 'routes/account.dart';
import 'routes/revisions.dart';
import 'routes/admin.dart';
import 'routes/audit.dart';
import 'routes/auth.dart';
import 'routes/devices.dart';
import 'routes/events.dart';
import 'routes/folders.dart';
import 'routes/health.dart';
import 'routes/info.dart';
import 'routes/invites.dart';
import 'routes/items.dart';
import 'routes/orgs.dart';
import 'routes/retention.dart';
import 'routes/setup.dart';
import 'routes/sync.dart';
import 'routes/teams.dart';

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
    final audit = AuditLog(clock, config.features, serverSecret);
    final deps = AppDeps._(
      config: config,
      db: db,
      clock: clock,
      log: log ?? Logger(config.logLevel, stdout.writeln),
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
      allowTestingKdf: allowTestingKdf,
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
  late final SecurityNotifier notifier = SecurityNotifier(this);

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

/// A team route: an org route, then the `teams` flag.
Handler _team(Handler inner) => _org(requireFeature(Flag.teams)(inner));

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
    ..put('/account/locale', requireAuth(setLocale))
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
    )
    ..post(
      '/orgs/<org>/invites',
      (Request r, String org) => _org((r) => createOrgInvite(r, org))(r),
    )
    ..get(
      '/orgs/<org>/invites',
      (Request r, String org) => _org((r) => listOrgInvites(r, org))(r),
    )
    ..delete(
      '/invites/<id>',
      (Request r, String id) => requireAuth((r) => revokeInvite(r, id))(r),
    )
    ..post('/invites/accept', acceptInvite)
    ..post('/invites/join', requireAuth(joinInvite))
    ..post(
      '/orgs/<org>/teams',
      (Request r, String org) => _team((r) => createTeam(r, org))(r),
    )
    ..put(
      '/orgs/<org>/teams/<team>',
      (Request r, String org, String team) =>
          _team((r) => updateTeam(r, org, team))(r),
    )
    ..delete(
      '/orgs/<org>/teams/<team>',
      (Request r, String org, String team) =>
          _team((r) => deleteTeamRoute(r, org, team))(r),
    )
    ..put(
      '/folders/<folder>/acl',
      (Request r, String folder) => _org((r) => putAcl(r, folder))(r),
    )
    ..put(
      '/folders/<folder>/keys',
      (Request r, String folder) => _org((r) => putFolderKeys(r, folder))(r),
    )
    ..post(
      '/folders/<folder>/rotation/done',
      (Request r, String folder) => _org((r) => rotationDone(r, folder))(r),
    )
    ..get('/admin/users', requireAuth(listUsers))
    ..put(
      '/admin/users/<id>',
      (Request r, String id) => requireAuth((r) => setDisabled(r, id))(r),
    )
    ..delete(
      '/admin/users/<id>',
      (Request r, String id) => requireAuth((r) => deleteUserRoute(r, id))(r),
    )
    ..get('/admin/orgs', requireAuth(listOrgs))
    ..delete(
      '/admin/orgs/<id>',
      (Request r, String id) => requireAuth((r) => adminDeleteOrg(r, id))(r),
    )
    ..post('/admin/invites', requireAuth(createInstanceInvite))
    ..get('/admin/invites', requireAuth(listInstanceInvites))
    ..get('/audit', requireAuth(requireFeature(Flag.audit)(getAudit)))
    ..get(
      '/orgs/<id>/settings/retention',
      (Request r, String id) => _org((r) => getRetention(r, id))(r),
    )
    ..post(
      '/events/ssh',
      requireAuth(requireFeature(Flag.clientEvents)(sshEvent)),
    )
    ..post(
      '/events/reveal',
      requireAuth(requireFeature(Flag.clientEvents)(revealEvent)),
    )
    ..get(
      '/items/<id>/revisions',
      (Request r, String id) => requireAuth(
        requireFeature(Flag.itemHistory)((r) => listRevisions(r, id)),
      )(r),
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
