// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../config/config.dart';
import '../../db/deletion.dart';
import '../../orgs/org_access.dart';
import '../app.dart';
import '../errors.dart';
import '../json.dart';
import '../middleware.dart';
import '../validate.dart';

Future<Response> createOrg(Request request) async {
  final deps = depsOf(request), auth = authOf(request);
  if (deps.config.orgCreation == OrgCreation.instanceOwner &&
      !auth.isInstanceOwner) {
    throw ApiError(
      ApiErrorCode.forbidden,
      'Only the Instance Owner creates organizations.',
    ); // 1.
  }
  final name = parseName((await readJson(request))['name']); // 2.
  final orgId = newId();
  await deps.db.transaction((tx) async {
    await checkMembershipCap(tx, deps.config, auth.userId); // 3.
    await tx.execute(
      "INSERT INTO orgs (id, name, settings, created_at) VALUES (@o, @n, '{}', @t)",
      {'o': orgId, 'n': name, 't': iso(deps.clock.now())},
    );
    await tx.execute(
      "INSERT INTO org_members (org_id, user_id, role, status) VALUES (@o, @u, 'owner', 'confirmed')",
      {'o': orgId, 'u': auth.userId},
    );
    await bumpOrgSeq(tx);
    // Audit hook: org.created [orgId] (org scope)
  });
  return jsonResponse({
    'org': {'id': orgId, 'name': name, 'role': 'owner'},
  }, status: 201);
}

const _settingKeys = {'mascot', 'auditDays', 'maxVersions', 'trashDays'};

Future<Response> updateOrg(Request request, String org) async {
  final deps = depsOf(request), auth = authOf(request);
  parseUuid(org);
  final body = await readJson(request);
  final sent = body['settings'] ?? const <String, Object?>{};
  if (sent is! Map<String, Object?> || !_settingKeys.containsAll(sent.keys)) {
    throw ApiError(
      ApiErrorCode.invalidRequest,
      'settings: mascot, auditDays, maxVersions or trashDays only.',
    ); // 1.
  }
  await deps.db.transaction((tx) async {
    await requireMember(tx, org, auth.userId, admin: true); // 2.
    final name = body.containsKey('name')
        ? parseName(body['name'])
        : null; // 3.
    final config = deps.config;
    final server = {
      'auditDays': config.auditRetentionDays,
      'maxVersions': config.itemHistoryMaxVersions,
      'trashDays': config.trashRetentionDays,
    };
    for (final MapEntry(:key, :value) in sent.entries) {
      if (value == null) continue;
      if (key == 'mascot') {
        if (value is! bool) {
          throw ApiError(
            ApiErrorCode.invalidRequest,
            'mascot must be a boolean or null.',
          ); // 4.
        }
      } else {
        _retention(key, value, server[key]!); // 5.
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
    // Audit hook: org.updated [orgId]
  });
  return noContent();
}

/// Org retention: int ≥ 1 and ≤ the server value (≤ 36500 when the server keeps forever);
/// auditDays also ≥ 30, or ≥ the server value when that is below 30.
int _retention(String key, Object? value, int server) {
  if (value is! int) {
    throw ApiError(
      ApiErrorCode.invalidRequest,
      '$key must be an integer or null.',
    );
  }
  final ceiling = server == 0 ? 36500 : server;
  final floor = key == 'auditDays'
      ? (server != 0 && server < 30 ? server : 30)
      : 1;
  if (value < floor || value > ceiling) {
    throw ApiError(
      ApiErrorCode.invalidRequest,
      '$key must be between $floor and $ceiling.',
    );
  }
  return value;
}

Future<Response> deleteOrgRoute(Request request, String org) async {
  final deps = depsOf(request), auth = authOf(request);
  parseUuid(org);
  await deps.db.transaction((tx) async {
    await requireMember(tx, org, auth.userId, owner: true); // 1. 404 · 2. 403
    await deleteOrg(tx, org);
    // Audit hook: org.deleted [orgId] (instance scope)
  });
  return noContent();
}
