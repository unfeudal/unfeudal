// SPDX-License-Identifier: Apache-2.0
part of 'api_client.dart';

/// The org routes: the org itself, its members, invites, teams, folder ACLs and folder keys.
class OrgApi {
  OrgApi._(this._client);

  final ApiClient _client;

  /// The server's retention values and the org's own (null = the server's applies), keyed by setting name.
  Future<({Map<String, int> server, Map<String, int?> org})> retention(
    String orgId,
  ) async {
    final json = await _client._send('GET', '/orgs/$orgId/settings/retention');
    if (json case {
      'server': {
        'auditDays': final int auditDays,
        'maxVersions': final int maxVersions,
        'trashDays': final int trashDays,
      },
      'org': {
        'auditDays': final int? orgAuditDays,
        'maxVersions': final int? orgMaxVersions,
        'trashDays': final int? orgTrashDays,
      },
    }) {
      return (
        server: {
          'auditDays': auditDays,
          'maxVersions': maxVersions,
          'trashDays': trashDays,
        },
        org: {
          'auditDays': orgAuditDays,
          'maxVersions': orgMaxVersions,
          'trashDays': orgTrashDays,
        },
      );
    }
    throw const FormatException('retention: unexpected body');
  }

  Future<({String id, String name, String role})> create(String name) async {
    final json = await _client._send('POST', '/orgs', body: {'name': name});
    if (json case {
      'org': {
        'id': final String id,
        'name': final String name,
        'role': final String role,
      },
    }) {
      return (id: id, name: name, role: role);
    }
    throw const FormatException('orgs: unexpected body');
  }

  Future<void> update(
    String orgId, {
    String? name,
    Map<String, Object?>? settings,
  }) => _client._send(
    'PUT',
    '/orgs/$orgId',
    body: {'name': ?name, 'settings': ?settings},
  );

  Future<void> delete(String orgId) => _client._send('DELETE', '/orgs/$orgId');

  Future<void> setMemberRole(String orgId, String userId, OrgRole role) =>
      _client._send(
        'PUT',
        '/orgs/$orgId/members/$userId',
        body: {'role': role.name},
      );

  Future<void> removeMember(String orgId, String userId) =>
      _client._send('DELETE', '/orgs/$orgId/members/$userId');

  Future<void> confirmMember(String orgId, String userId) =>
      _client._send('POST', '/orgs/$orgId/members/$userId/confirm');

  Future<InviteCreated> createInvite(
    String orgId, {
    required String email,
    OrgRole role = OrgRole.member,
  }) async => InviteCreated.fromJson(
    await _client._send(
      'POST',
      '/orgs/$orgId/invites',
      body: {'email': email, 'role': role.name},
    ),
  );

  Future<List<PendingInvite>> invites(String orgId) =>
      _client._list('/orgs/$orgId/invites', 'invites', PendingInvite.fromJson);

  Future<void> revokeInvite(String id) =>
      _client._send('DELETE', '/invites/$id');

  /// Joins the org of an invite with the signed-in account; returns its id.
  Future<String> joinInvite(String token) async {
    final json = await _client._send(
      'POST',
      '/invites/join',
      body: {'token': token},
    );
    if (json case {'orgId': final String orgId}) return orgId;
    throw const FormatException('invites/join: unexpected body');
  }

  Future<OrgTeam> createTeam(
    String orgId, {
    required String name,
    List<String> memberIds = const [],
  }) async {
    final json = await _client._send(
      'POST',
      '/orgs/$orgId/teams',
      body: {'name': name, 'memberIds': memberIds},
    );
    if (json case {'team': final Map<String, Object?> team}) {
      return OrgTeam.fromJson({...team, 'orgId': orgId});
    }
    throw const FormatException('teams: unexpected body');
  }

  Future<void> updateTeam(
    String orgId,
    String teamId, {
    String? name,
    List<String>? memberIds,
  }) => _client._send(
    'PUT',
    '/orgs/$orgId/teams/$teamId',
    body: {'name': ?name, 'memberIds': ?memberIds},
  );

  Future<void> deleteTeam(String orgId, String teamId) =>
      _client._send('DELETE', '/orgs/$orgId/teams/$teamId');

  Future<void> putAcl(String folderId, List<AclEntry> entries) => _client._send(
    'PUT',
    '/folders/$folderId/acl',
    body: {
      'entries': [
        for (final e in entries)
          {
            'principalType': e.principalType.name,
            'principalId': e.principalId,
            'allow': [for (final p in e.allow) p.name],
            'deny': [for (final p in e.deny) p.name],
          },
      ],
    },
  );

  /// Each wrap carries its recipient's `userId`.
  Future<void> putFolderKeys(
    String folderId, {
    required int version,
    required List<WrappedFolderKeys> wrapped,
    FolderKeyHistory? history,
  }) => _client._send(
    'PUT',
    '/folders/$folderId/keys',
    body: {
      'version': version,
      'wrapped': [for (final w in wrapped) w.toJson()],
      'history': history?.toJson(),
    },
  );

  Future<void> rotationDone(String folderId) =>
      _client._send('POST', '/folders/$folderId/rotation/done');
}
