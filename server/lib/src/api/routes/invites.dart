// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../auth/rate_limit.dart';
import '../../config/features.dart';
import '../../orgs/invites.dart';
import '../../orgs/org_access.dart';
import '../app.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';
import '../validate.dart';

Future<Response> createOrgInvite(Request request, String org) async {
  final deps = depsOf(request), auth = authOf(request);
  parseUuid(org);
  final body = await readJson(request);
  final email = normalizeEmail(body['email']); // 1.
  final role = body.containsKey('role')
      ? OrgRole.values.where((r) => r.name == body['role']).firstOrNull ??
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
    final locale =
        (await tx.query('SELECT locale FROM users WHERE id = @u', {
              'u': auth.userId,
            })).single['locale']!
            as String;
    return (caller, name, locale);
  });
  if (role != OrgRole.member && caller.role != OrgRole.owner) {
    throw ApiError(
      ApiErrorCode.forbidden,
      'Only an owner invites admins and owners.',
    ); // 3.
  }
  await deps.limiter.hit([inviteCreateKey(auth.userId)]); // 4.
  final row = await deps.db.transaction(
    (tx) => createInviteRow(
      tx,
      deps,
      email: email,
      orgId: org,
      role: role.name,
      createdBy: auth.userId,
    ),
  );
  // Audit hook: invite.created [inviteId]
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
Future<Response> listOrgInvites(Request request, String org) async {
  final deps = depsOf(request), auth = authOf(request);
  parseUuid(org);
  final rows = await deps.db.transaction((tx) async {
    await requireMember(tx, org, auth.userId, admin: true);
    return tx.query(
      'SELECT id, email, role, created_by, created_at, expires_at FROM invites '
      'WHERE org_id = @o AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > @now '
      'ORDER BY expires_at, id',
      {'o': org, 'now': iso(deps.clock.now())},
    );
  });
  return jsonResponse({
    'invites': [
      for (final r in rows)
        {
          'id': r['id'],
          'email': r['email'],
          'role': r['role'],
          'createdBy': r['created_by'],
          'createdAt': r['created_at'],
          'expiresAt': r['expires_at'],
        },
    ],
  });
}

Future<Response> revokeInvite(Request request, String id) async {
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
    if (!mayManage) throw ApiError(ApiErrorCode.notFound, 'Not found.'); // 1.
    if (orgId != null && !deps.features.enabled(Flag.orgs)) {
      throw ApiError(
        ApiErrorCode.featureDisabled,
        'Organizations are off on this server.',
      ); // 2.
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
      // Audit hook: invite.revoked [inviteId] (org scope, or instance scope)
    }
  });
  return noContent();
}
