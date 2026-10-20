// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../audit/audit_log.dart';
import '../../audit/retention_policy.dart';
import '../../config/config.dart';
import '../../db/deletion.dart';
import '../../orgs/org_access.dart';
import '../../orgs/rotations.dart';
import '../deps.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';
import '../request_audit.dart';
import '../validate.dart';

Future<Response> createOrg(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  if (deps.config.orgCreation == OrgCreation.instanceOwner &&
      !auth.isInstanceOwner) {
    throw ApiError(
      ApiErrorCode.forbidden,
      'Only the Instance Owner creates organizations.',
    );
  }
  final name = parseName((await readJson(request))['name']);
  final orgId = newId();
  await deps.db.transaction((tx) async {
    await checkMembershipCap(tx, deps.config, auth.userId);
    await tx.execute(
      "INSERT INTO orgs (id, name, settings, created_at) VALUES (@o, @n, '{}', @t)",
      {'o': orgId, 'n': name, 't': iso(deps.clock.now())},
    );
    await tx.execute(
      "INSERT INTO org_members (org_id, user_id, role, status) VALUES (@o, @u, 'owner', 'confirmed')",
      {'o': orgId, 'u': auth.userId},
    );
    await bumpOrgSeq(tx);
    await auditWriter(request, tx)(AuditScope.org(orgId), 'org.created', [
      orgId,
    ]);
  });
  return jsonResponse({
    'org': {'id': orgId, 'name': name, 'role': 'owner'},
  }, status: 201);
}

Future<Response> updateOrg(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  final org = parseUuid(request.params['org']!);
  final body = await readJson(request);
  final sent = body['settings'] ?? const <String, Object?>{};
  final server = serverRetention(deps.config);
  if (sent is! Map<String, Object?> ||
      !{'mascot', ...server.keys}.containsAll(sent.keys)) {
    throw ApiError.invalid(
      'settings: mascot, auditDays, maxVersions or trashDays only.',
    );
  }
  await deps.db.transaction((tx) async {
    await requireMember(tx, org, auth.userId, admin: true);
    final name = body.containsKey('name') ? parseName(body['name']) : null;
    for (final MapEntry(:key, :value) in sent.entries) {
      if (key == 'mascot') {
        if (value is! bool) {
          throw ApiError.invalid('mascot must be a boolean.');
        }
      } else if (value != null) {
        _retention(key, value, server[key]!);
      }
    }
    final row = (await tx.query(
      'SELECT name, settings FROM orgs WHERE id = @o',
      {'o': org},
    )).single;
    final settings =
        jsonDecode(row['settings']! as String) as Map<String, Object?>;
    final blockChanged =
        (name != null && name != row['name']) ||
        (sent.containsKey('mascot') && sent['mascot'] != settings['mascot']);
    for (final MapEntry(:key, :value) in sent.entries) {
      value == null ? settings.remove(key) : settings[key] = value;
    }
    await tx.execute(
      'UPDATE orgs SET name = @n, settings = @st WHERE id = @o',
      {'o': org, 'n': name ?? row['name'], 'st': jsonEncode(settings)},
    );
    // org_seq versions the block: name and mascot only
    if (blockChanged) await bumpOrgSeq(tx);
    await auditWriter(request, tx)(AuditScope.org(org), 'org.updated', [org]);
  });
  return noContent();
}

// An org may only shorten the server retention (36500 days at most when the
// server keeps forever); auditDays stays at 30 or more, unless the server is below 30.
int _retention(String key, Object? value, int server) {
  if (value is! int) {
    throw ApiError.invalid('$key must be an integer or null.');
  }
  final ceiling = server == 0 ? 36500 : server;
  final floor = key == 'auditDays'
      ? (server != 0 && server < 30 ? server : 30)
      : 1;
  if (value < floor || value > ceiling) {
    throw ApiError.invalid('$key must be between $floor and $ceiling.');
  }
  return value;
}

Future<Response> deleteOrgRoute(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  final org = parseUuid(request.params['org']!);
  await deps.db.transaction((tx) async {
    await requireMember(tx, org, auth.userId, owner: true);
    await deleteOrg(tx, org);
    await auditWriter(request, tx)(AuditScope.instance, 'org.deleted', [org]);
  });
  return noContent();
}

Future<Response> setRole(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  final (org, user) = _memberPath(request);
  final body = await readJson(request);
  final newRole = parseRole(body['role']);
  await deps.db.transaction((tx) async {
    final caller = await requireMember(tx, org, auth.userId, admin: true);
    await changeOrg(tx, org, reason: 'role_change', (before) async {
      final target = before.members[user] ?? (throw ApiError.notFound());
      requireRoleManager(caller, [
        target.role,
        newRole,
      ], 'Only an owner manages admins and owners.');
      if (newRole != OrgRole.owner && isLastOwner(before, user)) {
        throw lastOwnerError([before.name]);
      }
      await tx.execute(
        'UPDATE org_members SET role = @r WHERE org_id = @o AND user_id = @u',
        {'r': newRole.name, 'o': org, 'u': user},
      );
    });
    await auditWriter(request, tx)(AuditScope.org(org), 'member.role_changed', [
      user,
    ]);
  });
  return noContent();
}

Future<Response> removeMemberRoute(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  final (org, user) = _memberPath(request);
  await deps.db.transaction((tx) async {
    // Any status, so an unconfirmed member can still leave.
    final caller = await requireMember(tx, org, auth.userId, confirmed: false);
    final self = user == auth.userId;
    if (!self && !caller.isAdmin) {
      throw ApiError(ApiErrorCode.forbidden, 'Admins only.');
    }
    final before = (await loadOrg(tx, org))!;
    final target = before.members[user] ?? (throw ApiError.notFound());
    if (!self) {
      requireRoleManager(caller, [
        target.role,
      ], 'Only an owner removes admins and owners.');
    }
    if (isLastOwner(before, user)) throw lastOwnerError([before.name]);
    await removeMember(
      tx,
      org,
      user,
      reason: self ? 'member_left' : 'member_removed',
      before: before,
    );
    // the caller is the actor, so the member when they leave
    await auditWriter(request, tx)(AuditScope.org(org), 'member.removed', [
      user,
    ]);
  });
  return noContent();
}

Future<Response> confirmMember(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  final (org, user) = _memberPath(request);
  await deps.db.transaction((tx) async {
    await requireMember(tx, org, auth.userId, admin: true);
    final rows = await tx.query(
      'SELECT status FROM org_members WHERE org_id = @o AND user_id = @u',
      {'o': org, 'u': user},
    );
    if (rows.isEmpty) throw ApiError.notFound();
    if (rows.single['status'] != MemberStatus.accepted.name) {
      throw ApiError.invalid('Already confirmed.');
    }
    await tx.execute(
      "UPDATE org_members SET status = 'confirmed' WHERE org_id = @o AND user_id = @u",
      {'o': org, 'u': user},
    );
    await bumpOrgSeq(tx);
    await auditWriter(request, tx)(AuditScope.org(org), 'member.confirmed', [
      user,
    ]);
  });
  return noContent();
}

(String, String) _memberPath(Request request) =>
    (parseUuid(request.params['org']!), parseUuid(request.params['user']!));
