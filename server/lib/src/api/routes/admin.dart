// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../auth/rate_limit.dart';
import '../../db/deletion.dart';
import '../../orgs/invites.dart';
import '../../orgs/org_access.dart';
import '../../orgs/rotations.dart';
import '../app.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';
import '../validate.dart';

/// First line of every admin handler: the Instance Owner only, before the body is read.
void _requireIo(Request request) {
  if (!authOf(request).isInstanceOwner) {
    throw ApiError(ApiErrorCode.forbidden, 'Instance Owner only.');
  }
}

Future<Response> listUsers(Request request) async {
  _requireIo(request);
  final rows = await depsOf(request).db.query(
    'SELECT id, email, disabled, is_instance_owner, created_at FROM users ORDER BY email',
  );
  return jsonResponse({
    'users': [
      for (final r in rows)
        {
          'id': r['id'],
          'email': r['email'],
          'disabled': r['disabled'] == 1,
          'isInstanceOwner': r['is_instance_owner'] == 1,
          'createdAt': r['created_at'],
        },
    ],
  });
}

Future<Response> setDisabled(Request request, String id) async {
  _requireIo(request);
  final deps = depsOf(request);
  parseUuid(id);
  final disabled = (await readJson(request))['disabled'];
  if (disabled is! bool) {
    throw ApiError(
      ApiErrorCode.invalidRequest,
      'disabled must be a boolean.',
    ); // 1.
  }
  await deps.db.transaction((tx) async {
    final user = (await tx.query(
      'SELECT is_instance_owner FROM users WHERE id = @u',
      {'u': id},
    )).firstOrNull;
    if (user?['is_instance_owner'] == 1) {
      throw ApiError(
        ApiErrorCode.forbidden,
        'The Instance Owner cannot be disabled.',
      ); // 2.
    }
    if (user == null) throw ApiError(ApiErrorCode.notFound, 'Not found.'); // 3.
    if (disabled) {
      final last = await lastOwnerOrgs(tx, id);
      if (last.isNotEmpty) throw lastOwnerError(last); // 4.
    }
    final orgIds = [
      for (final r in await tx.query(
        'SELECT org_id FROM org_members WHERE user_id = @u',
        {'u': id},
      ))
        r['org_id']! as String,
    ];
    final before = {for (final o in orgIds) o: (await loadOrg(tx, o))!};
    await tx.execute('UPDATE users SET disabled = @d WHERE id = @u', {
      'd': disabled ? 1 : 0,
      'u': id,
    });
    for (final o in orgIds) {
      await recordRotations(
        tx,
        o,
        before[o]!,
        (await loadOrg(tx, o))!,
        'user_disabled',
      );
    }
    await bumpOrgSeq(tx);
    // Audit hook: admin.user_disabled | admin.user_enabled [userId] (instance scope and each org scope of the user)
  });
  return noContent();
}

Future<Response> deleteUserRoute(Request request, String id) async {
  _requireIo(request);
  final deps = depsOf(request), auth = authOf(request);
  parseUuid(id);
  // deleteUser refuses the Instance Owner (1.), an unknown id (2.) and a last owner (409)
  await deps.db.transaction((tx) => deleteUser(tx, id, actor: auth.userId));
  return noContent();
}

/// Metadata only: owner emails, member count, storage and last activity; never an item body.
Future<Response> listOrgs(Request request) async {
  _requireIo(request);
  final deps = depsOf(request);
  // ponytail: a few queries per org; one grouped query if an instance with many orgs shows up in profiles
  final orgs = await deps.db.transaction(readOnly: true, (tx) async {
    final out = <Map<String, Object?>>[];
    for (final o in await tx.query(
      'SELECT id, name FROM orgs ORDER BY name, id',
    )) {
      final p = {'o': o['id']};
      final owners = [
        for (final r in await tx.query(
          'SELECT u.email FROM org_members m JOIN users u ON u.id = m.user_id '
          "WHERE m.org_id = @o AND m.role = 'owner'",
          p,
        ))
          r['email']! as String,
      ]..sort();
      final members = (await tx.query(
        'SELECT count(*) AS n FROM org_members WHERE org_id = @o',
        p,
      )).single['n'];
      final items = (await tx.query(
        'SELECT CAST(COALESCE(SUM(size), 0) AS BIGINT) AS s, MAX(updated_at) AS at '
        'FROM items WHERE org_id = @o',
        p,
      )).single;
      final revisions =
          (await tx.query(
                'SELECT CAST(COALESCE(SUM(r.size), 0) AS BIGINT) AS s FROM item_revisions r '
                'JOIN items i ON i.id = r.item_id WHERE i.org_id = @o',
                p,
              )).single['s']!
              as int;
      out.add({
        'id': o['id'],
        'name': o['name'],
        'owners': owners,
        'memberCount': members,
        'storageBytes': (items['s']! as int) + revisions,
        'lastActivityAt': items['at'],
      });
    }
    return out;
  });
  return jsonResponse({'orgs': orgs});
}

/// The exact name confirms a deletion the Instance Owner cannot see inside.
Future<Response> adminDeleteOrg(Request request, String id) async {
  _requireIo(request);
  final deps = depsOf(request);
  parseUuid(id);
  final confirmName = (await readJson(request))['confirmName'];
  if (confirmName is! String) {
    throw ApiError(
      ApiErrorCode.invalidRequest,
      'confirmName must be a string.',
    ); // 1.
  }
  await deps.db.transaction((tx) async {
    final org = (await tx.query('SELECT name FROM orgs WHERE id = @o', {
      'o': id,
    })).firstOrNull;
    if (org == null) throw ApiError(ApiErrorCode.notFound, 'Not found.'); // 2.
    if (org['name'] != confirmName) {
      throw ApiError(
        ApiErrorCode.invalidRequest,
        'confirmName must be the exact organization name.',
      ); // 3.
    }
    await deleteOrg(tx, id);
    // Audit hook: org.deleted [orgId] (instance scope)
  });
  return noContent();
}

Future<Response> createInstanceInvite(Request request) async {
  _requireIo(request);
  final deps = depsOf(request), auth = authOf(request);
  final email = normalizeEmail((await readJson(request))['email']); // 1.
  await deps.limiter.hit([inviteCreateKey(auth.userId)]); // 2.
  final (row, locale) = await deps.db.transaction((tx) async {
    final row = await createInviteRow(
      tx,
      deps,
      email: email,
      createdBy: auth.userId,
    );
    final locale =
        (await tx.query('SELECT locale FROM users WHERE id = @u', {
              'u': auth.userId,
            })).single['locale']!
            as String;
    // Audit hook: invite.created [inviteId] (instance scope)
    return (row, locale);
  });
  final invite = await inviteBody(deps, row, email: email);
  final mailSent = await inviteMailSent(
    deps,
    to: email,
    locale: locale,
    vars: {'link': invite['link']! as String},
  );
  return jsonResponse({'invite': invite, 'mailSent': mailSent}, status: 201);
}

/// Pending instance invites (no org), by expiresAt.
Future<Response> listInstanceInvites(Request request) async {
  _requireIo(request);
  final deps = depsOf(request);
  final rows = await deps.db.query(
    'SELECT id, email, created_by, created_at, expires_at FROM invites '
    'WHERE org_id IS NULL AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > @now '
    'ORDER BY expires_at, id',
    {'now': iso(deps.clock.now())},
  );
  return jsonResponse({
    'invites': [
      for (final r in rows)
        {
          'id': r['id'],
          'email': r['email'],
          'createdBy': r['created_by'],
          'createdAt': r['created_at'],
          'expiresAt': r['expires_at'],
        },
    ],
  });
}
