// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../audit/audit_log.dart';
import '../../auth/rate_limit.dart';
import '../../auth/secret_hash.dart';
import '../../auth/tokens.dart';
import '../../config/features.dart';
import '../../db/db.dart';
import '../../net/client_ip.dart';
import '../../orgs/invites.dart';
import '../../orgs/org_access.dart';
import '../app.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';
import '../session.dart';
import '../validate.dart';

Future<Response> createOrgInvite(Request request) async {
  final org = request.params['org']!;
  final deps = depsOf(request), auth = authOf(request);
  parseUuid(org);
  final body = await readJson(request);
  final email = normalizeEmail(body['email']); // 1.
  final role = body.containsKey('role')
      ? OrgRole.values.asNameMap()[body['role']] ??
            (throw ApiError(
              ApiErrorCode.invalidRequest,
              'role must be owner, admin or member.',
            ))
      : OrgRole.member;
  final (caller, orgName, locale) = await deps.db.transaction((tx) async {
    final caller = await requireMember(tx, org, auth.userId, admin: true); // 2.
    final name =
        (await tx.query('SELECT name FROM orgs WHERE id = @o', {
              'o': org,
            })).single['name']!
            as String;
    final locale = await localeOf(tx, auth.userId);
    return (caller, name, locale);
  });
  if (role != OrgRole.member && caller.role != OrgRole.owner) {
    throw ApiError(
      ApiErrorCode.forbidden,
      'Only an owner invites admins and owners.',
    ); // 3.
  }
  await deps.limiter.hit([inviteCreateKey(auth.userId)]); // 4.
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
  final org = request.params['org']!;
  final deps = depsOf(request), auth = authOf(request);
  parseUuid(org);
  final invites = await deps.db.transaction((tx) async {
    await requireMember(tx, org, auth.userId, admin: true);
    return pendingInvites(tx, deps, org);
  });
  return jsonResponse({'invites': invites});
}

Future<Response> revokeInvite(Request request) async {
  final id = request.params['id']!;
  final deps = depsOf(request), auth = authOf(request);
  parseUuid(id);
  await deps.db.transaction((tx) async {
    final inv = (await tx.query(
      'SELECT org_id, role, accepted_at, revoked_at FROM invites WHERE id = @i',
      {'i': id},
    )).firstOrNull;
    final orgId = inv?['org_id'] as String?;
    MemberRow? caller;
    if (inv != null && orgId != null) {
      final row = (await tx.query(
        'SELECT role, status FROM org_members WHERE org_id = @o AND user_id = @u',
        {'o': orgId, 'u': auth.userId},
      )).firstOrNull;
      caller = row == null ? null : MemberRow.fromRow(row);
    }
    final mayManage =
        inv != null &&
        (orgId == null ? auth.isInstanceOwner : caller?.isAdmin == true);
    if (!mayManage) throw ApiError.notFound(); // 1.
    if (orgId != null && !deps.features.enabled(Flag.orgs)) {
      throw ApiError.orgsOff(); // 2.
    }
    if (orgId != null &&
        inv['role'] != 'member' &&
        caller!.role != OrgRole.owner) {
      throw ApiError(
        ApiErrorCode.forbidden,
        'Only an owner revokes admin and owner invites.',
      ); // 3.
    }
    if (inv['accepted_at'] != null) {
      throw ApiError(ApiErrorCode.conflict, 'Already accepted.'); // 4.
    }
    if (inv['revoked_at'] == null) {
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

const _invalid = 'This invitation is not valid.';

/// Row of a usable invite for [email], or null (unknown, used, revoked, expired, other email).
Future<Map<String, Object?>?> _usable(
  Tx tx,
  String token,
  String email,
  DateTime now,
) async {
  final r = (await tx.query(
    'SELECT i.id, i.email, i.org_id, i.role, i.accepted_at, i.revoked_at, i.expires_at, '
    'COALESCE(u.is_instance_owner, 0) AS by_io FROM invites i LEFT JOIN users u ON u.id = i.created_by '
    'WHERE i.token_hash = @h',
    {'h': hashToken(token)},
  )).firstOrNull;
  if (r == null || r['accepted_at'] != null || r['revoked_at'] != null) {
    return null;
  }
  if (!parseIso(r['expires_at']! as String).isAfter(now) ||
      r['email'] != email) {
    return null;
  }
  return r;
}

/// First write of accept and join: a concurrent accept that committed first leaves 0 rows → 404.
Future<void> _claim(Tx tx, Map<String, Object?> inv, DateTime now) async {
  final n = await tx.execute(
    'UPDATE invites SET accepted_at = @t WHERE id = @i AND accepted_at IS NULL',
    {'t': iso(now), 'i': inv['id']},
  );
  if (n == 0) throw ApiError(ApiErrorCode.notFound, _invalid);
}

void _orgGates(AppDeps deps, Map<String, Object?> inv) {
  if (inv['org_id'] == null) return;
  if (!deps.features.enabled(Flag.orgs)) {
    throw ApiError.orgsOff();
  }
  if (!deps.features.enabled(Flag.invitesFromOrgs) && inv['by_io'] != 1) {
    throw ApiError(ApiErrorCode.notFound, _invalid);
  }
}

Future<Response> acceptInvite(Request request) async {
  final deps = depsOf(request);
  final net = netOf(clientIp(request, deps.config.trustedProxies));
  await deps.limiter.hit([inviteIpKey(net)]); // 1.
  final body = await readJson(request); // 2.
  final token = reqString(body, 'token', max: 200);
  final email = normalizeEmail(body['email']);
  final now = deps.clock.now();
  final inv =
      await deps.db.transaction(
        readOnly: true,
        (tx) => _usable(tx, token, email, now),
      ) ??
      (throw ApiError(ApiErrorCode.notFound, _invalid)); // 3.
  _orgGates(deps, inv); // 4, 5.
  Future<void> noAccount(Tx tx) async {
    if ((await tx.query('SELECT 1 AS x FROM users WHERE email = @e', {
      'e': email,
    })).isNotEmpty) {
      throw ApiError(
        ApiErrorCode.conflict,
        'An account already uses this email.',
        extra: {'reason': 'account_exists'},
      ); // 6.
    }
  }

  await deps.db.transaction(readOnly: true, noAccount);
  final bundle = body['bundle']; // 7.
  parseBundle(bundle, allowTestingKdf: deps.allowTestingKdf);
  final device = parseDevice(body['device']);
  final authHash = await hashSecret(
    reqKey32(body, 'authKey'),
    deps.secretHash,
  ); // Argon2 before the transaction
  final recoveryHash = await hashSecret(
    reqKey32(body, 'recoveryAuthKey'),
    deps.secretHash,
  );
  final locale = body.containsKey('locale')
      ? parseLocale(body['locale'])
      : 'en';
  final session = await deps.db.transaction((tx) async {
    final again =
        await _usable(tx, token, email, deps.clock.now()) ??
        (throw ApiError(ApiErrorCode.notFound, _invalid)); // 8.
    await _claim(tx, again, deps.clock.now());
    await noAccount(tx);
    final userId = newId();
    await tx.execute(
      'INSERT INTO users (id, email, bundle, bundle_version, auth_hash, recovery_auth_hash, created_at, locale) '
      'VALUES (@id, @e, @b, 0, @a, @r, @t, @l)',
      {
        'id': userId,
        'e': email,
        'b': jsonEncode(bundle),
        'a': authHash,
        'r': recoveryHash,
        't': iso(deps.clock.now()),
        'l': locale,
      },
    );
    final orgId = again['org_id'] as String?;
    if (orgId != null) {
      await checkMembershipCap(tx, deps.config, userId);
      await tx.execute(
        "INSERT INTO org_members (org_id, user_id, role, status) VALUES (@o, @u, @r, 'accepted')",
        {'o': orgId, 'u': userId, 'r': again['role']},
      );
      await bumpOrgSeq(tx);
    }
    final session = await createSession(
      deps,
      tx,
      userId: userId,
      isInstanceOwner: false,
      bundle: bundle as Map<String, Object?>,
      bundleVersion: 0,
      device: device,
    );
    // after the session exists: the new user and device are the actors
    final audit = auditWriter(
      request,
      tx,
      actor: (user: userId, device: session.deviceId),
    );
    await audit(
      orgId == null ? AuditScope.instance : AuditScope.org(orgId),
      'invite.accepted',
      [again['id']! as String, userId],
    );
    await audit(AuditScope.user(userId), 'device.added', [session.deviceId]);
    return session;
  });
  await deps.limiter.refund(inviteIpKey(net));
  return jsonResponse(session.toJson(), status: 201);
}

Future<Response> joinInvite(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  final net = netOf(clientIp(request, deps.config.trustedProxies));
  await deps.limiter.hit([inviteIpKey(net)]); // 1.
  final token = reqString(await readJson(request), 'token', max: 200); // 2.
  final orgId = await deps.db.transaction((tx) async {
    final email =
        (await tx.query('SELECT email FROM users WHERE id = @u', {
              'u': auth.userId,
            })).single['email']!
            as String;
    final inv =
        await _usable(tx, token, email, deps.clock.now()) ??
        (throw ApiError(ApiErrorCode.notFound, _invalid)); // 3.
    final orgId = inv['org_id'] as String?;
    if (orgId == null) {
      throw ApiError(
        ApiErrorCode.conflict,
        'This invitation creates an account.',
        extra: {'reason': 'account_exists'},
      ); // 4.
    }
    _orgGates(deps, inv); // 5, 6.
    await _claim(tx, inv, deps.clock.now());
    final member = (await tx.query(
      'SELECT 1 AS x FROM org_members WHERE org_id = @o AND user_id = @u',
      {'o': orgId, 'u': auth.userId},
    )).isNotEmpty;
    if (!member) {
      await checkMembershipCap(tx, deps.config, auth.userId); // 7.
      await tx.execute(
        "INSERT INTO org_members (org_id, user_id, role, status) VALUES (@o, @u, @r, 'accepted')",
        {'o': orgId, 'u': auth.userId, 'r': inv['role']},
      );
    }
    await bumpOrgSeq(tx);
    await auditWriter(request, tx)(AuditScope.org(orgId), 'invite.accepted', [
      inv['id']! as String,
      auth.userId,
    ]);
    return orgId;
  });
  await deps.limiter.refund(inviteIpKey(net));
  return jsonResponse({'orgId': orgId});
}
