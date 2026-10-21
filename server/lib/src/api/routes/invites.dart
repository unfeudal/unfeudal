// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../audit/audit_log.dart';
import '../../auth/rate_limit.dart';
import '../../auth/secret_hash.dart';
import '../../auth/tokens.dart';
import '../../db/db.dart';
import '../../mail/templates.dart';
import '../../net/client_ip.dart';
import '../../orgs/invites.dart';
import '../../orgs/org_access.dart';
import '../deps.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';
import '../request_audit.dart';
import '../session.dart';
import '../validate.dart';

Future<Response> createOrgInvite(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  final org = parseUuid(request.params['org']!);
  final body = await readJson(request);
  final email = normalizeEmail(body['email']);
  final role = body.containsKey('role')
      ? parseRole(body['role'])
      : OrgRole.member;
  final (caller, orgName, locale) = await deps.db.transaction((tx) async {
    final caller = await requireMember(tx, org, auth.userId, admin: true);
    final name =
        (await tx.query('SELECT name FROM orgs WHERE id = @o', {
              'o': org,
            })).single['name']!
            as String;
    final locale = await localeOf(tx, auth.userId);
    return (caller, name, locale);
  });
  requireRoleManager(caller, [
    role,
  ], 'Only an owner invites admins and owners.');
  await deps.limiter.hit([inviteCreateKey(auth.userId)]);
  final row = await deps.db.transaction((tx) async {
    final row = await createInviteRow(
      tx,
      deps,
      email: email,
      orgId: org,
      role: role.name,
      createdBy: auth.userId,
    );
    await auditWriter(request, tx)(AuditScope.org(org), 'invite.created', [
      row.id,
    ]);
    return row;
  });
  final invite = await inviteBody(deps, row, email: email, role: role.name);
  final mailSent = await inviteMailSent(
    deps,
    to: email,
    locale: locale,
    vars: {'link': invite['link']! as String, 'orgName': orgName},
  );
  return jsonResponse({'invite': invite, 'mailSent': mailSent}, status: 201);
}

/// Pending invites only (not accepted, revoked or expired), by expiresAt.
Future<Response> listOrgInvites(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  final org = parseUuid(request.params['org']!);
  final invites = await deps.db.transaction((tx) async {
    await requireMember(tx, org, auth.userId, admin: true);
    return pendingInvites(tx, deps, org);
  });
  return jsonResponse({'invites': invites});
}

Future<Response> revokeInvite(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  final id = parseUuid(request.params['id']!);
  await deps.db.transaction((tx) async {
    final invite = (await tx.query(
      'SELECT org_id, role, accepted_at, revoked_at FROM invites WHERE id = @i',
      {'i': id},
    )).firstOrNull;
    final orgId = invite?['org_id'] as String?;
    MemberRow? caller;
    if (invite != null && orgId != null) {
      final row = (await tx.query(
        'SELECT role, status FROM org_members WHERE org_id = @o AND user_id = @u',
        {'o': orgId, 'u': auth.userId},
      )).firstOrNull;
      caller = row == null ? null : MemberRow.fromRow(row);
    }
    final mayManage =
        invite != null &&
        (orgId == null ? auth.isInstanceOwner : caller?.isAdmin == true);
    // An invite the caller may not manage looks the same as a missing one.
    if (!mayManage) throw ApiError.notFound();
    if (orgId != null && !deps.features.enabled(Flag.orgs)) {
      throw ApiError.orgsOff();
    }
    if (orgId != null) {
      requireRoleManager(caller!, [
        OrgRole.values.asNameMap()[invite['role']] ?? OrgRole.admin,
      ], 'Only an owner revokes admin and owner invites.');
    }
    if (invite['accepted_at'] != null) {
      throw ApiError(ApiErrorCode.conflict, 'Already accepted.');
    }
    if (invite['revoked_at'] == null) {
      await tx.execute('UPDATE invites SET revoked_at = @t WHERE id = @i', {
        't': iso(deps.clock.now()),
        'i': id,
      });
      await auditWriter(request, tx)(
        orgId == null ? AuditScope.instance : AuditScope.org(orgId),
        'invite.revoked',
        [id],
      );
    }
  });
  return noContent();
}

const _invalidInviteMessage = 'This invitation is not valid.';

// An unknown, used, revoked or expired invite, or one for another email, gives
// the same 404.
Future<Map<String, Object?>> _requireUsableInvite(
  Tx tx,
  String token, {
  required String email,
  required DateTime now,
}) async {
  final r = (await tx.query(
    'SELECT i.id, i.email, i.org_id, i.role, i.accepted_at, i.revoked_at, i.expires_at, '
    'COALESCE(u.is_instance_owner, 0) AS created_by_instance_owner FROM invites i LEFT JOIN users u ON u.id = i.created_by '
    'WHERE i.token_hash = @h',
    {'h': hashToken(token)},
  )).firstOrNull;
  if (r == null ||
      r['accepted_at'] != null ||
      r['revoked_at'] != null ||
      !parseIso(r['expires_at']! as String).isAfter(now) ||
      r['email'] != email) {
    throw ApiError.notFound(_invalidInviteMessage);
  }
  return r;
}

// Runs as the first write of accept and join: when a concurrent accept
// committed first, no row changes and the caller gets a 404.
Future<void> _claim(Tx tx, Map<String, Object?> invite, DateTime now) async {
  final n = await tx.execute(
    'UPDATE invites SET accepted_at = @t WHERE id = @i AND accepted_at IS NULL',
    {'t': iso(now), 'i': invite['id']},
  );
  if (n == 0) throw ApiError.notFound(_invalidInviteMessage);
}

void _requireOrgInviteAllowed(AppDeps deps, Map<String, Object?> invite) {
  if (invite['org_id'] == null) return;
  if (!deps.features.enabled(Flag.orgs)) {
    throw ApiError.orgsOff();
  }
  if (!deps.features.enabled(Flag.invitesFromOrgs) &&
      invite['created_by_instance_owner'] != 1) {
    throw ApiError.notFound(_invalidInviteMessage);
  }
}

Future<void> _requireNoAccount(Tx tx, String email) async {
  if ((await tx.query('SELECT 1 AS x FROM users WHERE email = @e', {
    'e': email,
  })).isNotEmpty) {
    throw ApiError(
      ApiErrorCode.conflict,
      'An account already uses this email.',
      extra: {'reason': ConflictReason.accountExists.wire},
    );
  }
}

Future<String?> _joinInvitedOrg(
  Tx tx,
  AppDeps deps, {
  required Map<String, Object?> invite,
  required String userId,
}) async {
  final orgId = invite['org_id'] as String?;
  if (orgId != null) {
    await checkMembershipCap(tx, deps.config, userId);
    await tx.execute(
      "INSERT INTO org_members (org_id, user_id, role, status) VALUES (@o, @u, @r, 'accepted')",
      {'o': orgId, 'u': userId, 'r': invite['role']},
    );
    await bumpOrgSeq(tx);
  }
  return orgId;
}

Future<void> _requireAcceptable(
  AppDeps deps,
  String token,
  String email,
) async {
  final now = deps.clock.now();
  final invite = await deps.db.transaction(
    readOnly: true,
    (tx) => _requireUsableInvite(tx, token, email: email, now: now),
  );
  _requireOrgInviteAllowed(deps, invite);
  await deps.db.transaction(
    readOnly: true,
    (tx) => _requireNoAccount(tx, email),
  );
}

Future<(String, String)> _hashAuthKeys(
  Map<String, Object?> body,
  SecretHashParams params,
) async => (
  await hashSecret(parseKey32(body, 'authKey'), params),
  await hashSecret(parseKey32(body, 'recoveryAuthKey'), params),
);

Future<Response> acceptInvite(Request request) async {
  final deps = depsOf(request);
  final net = netOf(clientIpOf(request));
  await deps.limiter.hit([inviteIpKey(net)]);
  final body = await readJson(request);
  final token = parseRequiredString(body, 'token', max: 200);
  final email = normalizeEmail(body['email']);
  await _requireAcceptable(deps, token, email);
  final bundle = parseBundle(body['bundle'], kdfFloor: deps.kdfFloor);
  final device = parseDevice(body['device']);
  // Argon2 is slow, so both hashes run before the write transaction opens.
  final (authHash, recoveryHash) = await _hashAuthKeys(body, deps.secretHash);
  final locale = body.containsKey('locale')
      ? parseLocale(body['locale'])
      : defaultLocale;
  final session = await deps.db.transaction((tx) async {
    // Checks again inside the write transaction: the invite may have changed
    // since the read-only check.
    final again = await _requireUsableInvite(
      tx,
      token,
      email: email,
      now: deps.clock.now(),
    );
    await _claim(tx, again, deps.clock.now());
    await _requireNoAccount(tx, email);
    final userId = await insertUser(
      tx,
      deps,
      email: email,
      bundle: bundle,
      authHash: authHash,
      recoveryHash: recoveryHash,
      locale: locale,
      isInstanceOwner: false,
    );
    final orgId = await _joinInvitedOrg(
      tx,
      deps,
      invite: again,
      userId: userId,
    );
    final session = await createSession(
      request,
      tx,
      userId: userId,
      isInstanceOwner: false,
      bundle: bundle,
      bundleVersion: 0,
      device: device,
    );
    // after the session exists: the new user and device are the actors
    await auditWriter(
      request,
      tx,
      actor: (user: userId, device: session.deviceId),
    )(
      orgId == null ? AuditScope.instance : AuditScope.org(orgId),
      'invite.accepted',
      [again['id']! as String, userId],
    );
    return session;
  });
  await deps.limiter.refund(inviteIpKey(net));
  return jsonResponse(session.toJson(), status: 201);
}

Future<Response> joinInvite(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  final net = netOf(clientIpOf(request));
  await deps.limiter.hit([inviteIpKey(net)]);
  final token = parseRequiredString(await readJson(request), 'token', max: 200);
  final orgId = await deps.db.transaction((tx) async {
    final email =
        (await tx.query('SELECT email FROM users WHERE id = @u', {
              'u': auth.userId,
            })).single['email']!
            as String;
    final invite = await _requireUsableInvite(
      tx,
      token,
      email: email,
      now: deps.clock.now(),
    );
    final orgId = invite['org_id'] as String?;
    if (orgId == null) {
      throw ApiError(
        ApiErrorCode.conflict,
        'This invitation creates an account.',
        extra: {'reason': ConflictReason.accountExists.wire},
      );
    }
    _requireOrgInviteAllowed(deps, invite);
    await _claim(tx, invite, deps.clock.now());
    final isMember = (await tx.query(
      'SELECT 1 AS x FROM org_members WHERE org_id = @o AND user_id = @u',
      {'o': orgId, 'u': auth.userId},
    )).isNotEmpty;
    if (!isMember) {
      await checkMembershipCap(tx, deps.config, auth.userId);
      await tx.execute(
        "INSERT INTO org_members (org_id, user_id, role, status) VALUES (@o, @u, @r, 'accepted')",
        {'o': orgId, 'u': auth.userId, 'r': invite['role']},
      );
    }
    await bumpOrgSeq(tx);
    await auditWriter(request, tx)(AuditScope.org(orgId), 'invite.accepted', [
      invite['id']! as String,
      auth.userId,
    ]);
    return orgId;
  });
  await deps.limiter.refund(inviteIpKey(net));
  return jsonResponse({'orgId': orgId});
}
