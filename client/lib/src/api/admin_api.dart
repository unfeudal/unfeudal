// SPDX-License-Identifier: Apache-2.0
part of 'api_client.dart';

/// The Instance Owner's routes under `/admin`.
class AdminApi {
  AdminApi._(this._client);

  final ApiClient _client;

  Future<List<AdminUser>> users() =>
      _client._list('/admin/users', 'users', AdminUser.fromJson);

  Future<void> setDisabled(String userId, {required bool disabled}) => _client
      ._send('PUT', '/admin/users/$userId', body: {'disabled': disabled});

  Future<void> deleteUser(String userId) =>
      _client._send('DELETE', '/admin/users/$userId');

  Future<List<AdminOrg>> orgs() =>
      _client._list('/admin/orgs', 'orgs', AdminOrg.fromJson);

  Future<void> deleteOrg(String orgId, String confirmName) => _client._send(
    'DELETE',
    '/admin/orgs/$orgId',
    body: {'confirmName': confirmName},
  );

  Future<InviteCreated> invite(String email) async => InviteCreated.fromJson(
    await _client._send('POST', '/admin/invites', body: {'email': email}),
  );

  Future<List<PendingInvite>> invites() =>
      _client._list('/admin/invites', 'invites', PendingInvite.fromJson);
}
