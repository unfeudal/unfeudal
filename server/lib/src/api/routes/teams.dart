// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../audit/audit_log.dart';
import '../../db/db.dart';
import '../../db/deletion.dart';
import '../../orgs/org_access.dart';
import '../../orgs/rotations.dart';
import '../app.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';
import '../validate.dart';

/// Absent → []; at most 500 distinct members of the org (any status) whose account is not disabled.
List<String> _memberIds(Object? v, OrgSnapshot org) {
  if (v == null) return const [];
  if (v is! List || v.length > 500) {
    throw ApiError(
      ApiErrorCode.invalidRequest,
      'memberIds must be a list of at most 500 ids.',
    );
  }
  final ids = <String>{};
  for (final id in v) {
    final member = id is String ? org.members[id] : null;
    if (member == null || member.disabled || !ids.add(id as String)) {
      throw ApiError(
        ApiErrorCode.invalidRequest,
        'memberIds must name distinct, enabled members of the organization.',
      );
    }
  }
  return ids.toList();
}

Future<void> _nameFree(Tx tx, String org, String name, {String? except}) async {
  final taken = await tx.query(
    'SELECT id FROM teams WHERE org_id = @o AND name = @n',
    {'o': org, 'n': name},
  );
  if (taken.any((r) => r['id'] != except)) {
    throw ApiError(ApiErrorCode.conflict, 'Another team has this name.');
  }
}

Future<void> _seat(Tx tx, String org, String team, List<String> ids) async {
  for (final userId in ids) {
    await tx.execute(
      'INSERT INTO team_members (org_id, team_id, user_id) VALUES (@o, @t, @u)',
      {'o': org, 't': team, 'u': userId},
    );
  }
}

Future<void> _requireTeam(Tx tx, String org, String team) async {
  final rows = await tx.query(
    'SELECT 1 AS x FROM teams WHERE org_id = @o AND id = @t',
    {'o': org, 't': team},
  );
  if (rows.isEmpty) throw ApiError.notFound();
}

Future<Response> createTeam(Request request) async {
  final org = request.params['org']!;
  final deps = depsOf(request), auth = authOf(request);
  parseUuid(org);
  final body = await readJson(request);
  final name = parseName(body['name']); // 1.
  final teamId = newId();
  final memberIds = await deps.db.transaction((tx) async {
    await requireMember(tx, org, auth.userId, admin: true); // 2.
    final ids = _memberIds(body['memberIds'], (await loadOrg(tx, org))!); // 3.
    await _nameFree(tx, org, name); // 4.
    await tx.execute(
      'INSERT INTO teams (id, org_id, name) VALUES (@t, @o, @n)',
      {'t': teamId, 'o': org, 'n': name},
    );
    await _seat(tx, org, teamId, ids);
    await bumpOrgSeq(tx);
    await auditWriter(request, tx)(AuditScope.org(org), 'team.created', [
      teamId,
    ]);
    return ids;
  });
  return jsonResponse({
    'team': {'id': teamId, 'name': name, 'memberIds': memberIds},
  }, status: 201);
}

Future<Response> updateTeam(Request request) async {
  final org = request.params['org']!, team = request.params['team']!;
  final deps = depsOf(request), auth = authOf(request);
  parseUuid(org);
  parseUuid(team);
  final body = await readJson(request);
  await deps.db.transaction((tx) async {
    await requireMember(tx, org, auth.userId, admin: true); // 1.
    await _requireTeam(tx, org, team); // 2.
    final before = (await loadOrg(tx, org))!;
    if (body.containsKey('name')) {
      final name = parseName(body['name']); // 3.
      await _nameFree(tx, org, name, except: team);
      await tx.execute('UPDATE teams SET name = @n WHERE id = @t', {
        'n': name,
        't': team,
      });
    }
    if (body.containsKey('memberIds')) {
      final ids = _memberIds(body['memberIds'], before); // 4.
      await tx.execute('DELETE FROM team_members WHERE team_id = @t', {
        't': team,
      });
      await _seat(tx, org, team, ids);
    }
    await recordRotations(
      tx,
      org,
      before,
      (await loadOrg(tx, org))!,
      'team_change',
    );
    await bumpOrgSeq(tx);
    await auditWriter(request, tx)(AuditScope.org(org), 'team.updated', [team]);
  });
  return noContent();
}

Future<Response> deleteTeamRoute(Request request) async {
  final org = request.params['org']!, team = request.params['team']!;
  final deps = depsOf(request), auth = authOf(request);
  parseUuid(org);
  parseUuid(team);
  await deps.db.transaction((tx) async {
    await requireMember(tx, org, auth.userId, admin: true); // 1.
    await _requireTeam(tx, org, team); // 2.
    await deleteTeam(tx, org, team);
    await auditWriter(request, tx)(AuditScope.org(org), 'team.deleted', [team]);
  });
  return noContent();
}
