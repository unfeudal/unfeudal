// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../auth/secret_hash.dart';
import 'credentials.dart';
import 'deps.dart';
import 'errors.dart';
import 'middleware.dart';
import 'routes/account.dart';
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
import 'routes/revisions.dart';
import 'routes/setup.dart';
import 'routes/sync.dart';
import 'routes/teams.dart';

export 'deps.dart';

Never _notFound(Request _) => throw ApiError.notFound();

Handler _org(Handler inner) => requireAuth(requireFeature(Flag.orgs)(inner));

Handler _team(Handler inner) => _org(requireFeature(Flag.teams)(inner));

Handler _credentials(Handler inner) =>
    credentialCheck(HashPriority.other)(inner);

void _addAccountRoutes(Router api) {
  api
    ..post('/setup', setup)
    ..post('/prelogin', prelogin)
    ..post('/login', credentialCheck(HashPriority.signIn)(login))
    ..post('/token/refresh', refreshToken)
    ..post('/account/password', requireAuth(_credentials(changePassword)))
    ..post(
      '/account/recover/start',
      requireFeature(Flag.recoveryKit)(_credentials(recoverStart)),
    )
    ..post(
      '/account/recover',
      requireFeature(Flag.recoveryKit)(_credentials(recover)),
    )
    ..post(
      '/account/recovery-kit',
      requireAuth(requireFeature(Flag.recoveryKit)(_credentials(recoveryKit))),
    )
    ..put('/account/locale', requireAuth(setLocale))
    ..delete('/account', requireAuth(_credentials(deleteAccount)))
    ..get('/devices', requireAuth(listDevices))
    ..delete('/devices/<id>', requireAuth(deleteDevice));
}

void _addItemAndOrgRoutes(Router api) {
  api
    ..put('/items/<id>', requireAuth(putItem))
    ..get('/sync', requireAuth(sync))
    ..post('/orgs', _org(createOrg))
    ..put('/orgs/<org>', _org(updateOrg))
    ..delete('/orgs/<org>', _org(deleteOrgRoute))
    ..put('/orgs/<org>/members/<user>', _org(setRole))
    ..delete('/orgs/<org>/members/<user>', _org(removeMemberRoute))
    ..post('/orgs/<org>/members/<user>/confirm', _org(confirmMember))
    ..post('/orgs/<org>/invites', _org(createOrgInvite))
    ..get('/orgs/<org>/invites', _org(listOrgInvites))
    ..delete('/invites/<id>', requireAuth(revokeInvite))
    ..post('/invites/accept', acceptInvite)
    ..post('/invites/join', requireAuth(joinInvite))
    ..post('/orgs/<org>/teams', _team(createTeam))
    ..put('/orgs/<org>/teams/<team>', _team(updateTeam))
    ..delete('/orgs/<org>/teams/<team>', _team(deleteTeamRoute))
    ..put('/folders/<folder>/acl', _org(putAcl))
    ..put('/folders/<folder>/keys', _org(putFolderKeys))
    ..post('/folders/<folder>/rotation/done', _org(rotationDone));
}

void _addAdminAndEventRoutes(Router api) {
  api
    ..get('/admin/users', requireAuth(listUsers))
    ..put('/admin/users/<id>', requireAuth(setDisabled))
    ..delete('/admin/users/<id>', requireAuth(deleteUserRoute))
    ..get('/admin/orgs', requireAuth(listOrgs))
    ..delete('/admin/orgs/<id>', requireAuth(adminDeleteOrg))
    ..post('/admin/invites', requireAuth(createInstanceInvite))
    ..get('/admin/invites', requireAuth(listInstanceInvites))
    ..get('/audit', requireAuth(requireFeature(Flag.audit)(getAudit)))
    ..get('/orgs/<id>/settings/retention', _org(retentionSettings))
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
      requireAuth(requireFeature(Flag.itemHistory)(listRevisions)),
    );
}

/// Middleware order, outermost first: withDeps, requestLog, securityHeaders,
/// errorMapper, then the routes.
Handler buildHandler(AppDeps deps) {
  final api = Router(notFoundHandler: _notFound);
  _addAccountRoutes(api);
  _addItemAndOrgRoutes(api);
  _addAdminAndEventRoutes(api);
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
