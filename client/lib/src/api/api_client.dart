// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../debug_trace.dart';
import '../version.dart';
import 'admin_models.dart';

/// A non-2xx answer. [code] keeps an unknown wire code; [known] is null for it.
class ApiException implements Exception {
  ApiException(
    this.code,
    this.status, {
    this.message = '',
    this.reason,
    this.item,
    this.orgs,
    this.retryAfter,
  });

  final String code;
  final int status;
  final String message;
  final String? reason;
  final Item? item;
  final List<String>? orgs;
  final Duration? retryAfter;

  ApiErrorCode? get known => ApiErrorCode.fromWire(code);

  @override
  String toString() =>
      'ApiException($status $code${reason == null ? '' : ' $reason'})';
}

/// The server could not be reached: socket, TLS, timeout.
class NetworkException implements Exception {
  NetworkException(this.cause);
  final Object cause;

  @override
  String toString() => 'NetworkException($cause)';
}

/// A write refused locally because the client is read-only toward this server.
class ReadOnlyException implements Exception {
  const ReadOnlyException([this.reason]);
  final String? reason;
}

typedef DeviceInput = ({String name, String platform});

/// The server's retention values and the org's own (null = the server's applies).
typedef OrgRetention = ({
  ({int auditDays, int maxVersions, int trashDays}) server,
  ({int? auditDays, int? maxVersions, int? trashDays}) org,
});

class ApiClient {
  ApiClient(this.baseUrl, this._http);

  final Uri baseUrl;
  final http.Client _http;
  String? accessToken;
  String? refreshToken;

  /// Must persist the new pair before it resolves: a lost refresh token revokes the device on replay.
  Future<void> Function(TokenPair)? onTokens;
  bool readOnly = false;
  Future<void> Function(Duration) sleep = Future.delayed;

  static const _timeout = Duration(seconds: 30);

  Future<({Uint8List salt, KdfParams kdf})> prelogin(String email) async {
    final json = await _send(
      'POST',
      '/prelogin',
      body: {'email': email},
      auth: false,
    );
    if (json case {'salt': final String salt, 'kdf': final Object kdf}) {
      return (salt: unb64(salt), kdf: KdfParams.fromJson(kdf));
    }
    throw const FormatException('prelogin: unexpected body');
  }

  /// Creates the account: the owner with a setup token, a member with an invite token.
  Future<Session> enroll(
    EnrollKind kind, {
    required String token,
    required String email,
    required AccountBundle bundle,
    required List<int> authKey,
    required List<int> recoveryAuthKey,
    required DeviceInput device,
    String? locale,
  }) => _session(kind == EnrollKind.setup ? '/setup' : '/invites/accept', {
    'token': token,
    'email': email,
    'bundle': bundle.toJson(),
    'authKey': b64(authKey),
    'recoveryAuthKey': b64(recoveryAuthKey),
    'device': _device(device),
    'locale': ?locale,
  });

  Future<Session> login({
    required String email,
    required List<int> authKey,
    required DeviceInput device,
  }) => _session('/login', {
    'email': email,
    'authKey': b64(authKey),
    'device': _device(device),
  });

  Future<TokenPair> refresh() async {
    if (tracing(TraceArea.session)) {
      trace(TraceArea.session, 'refresh with #${await tokenTag(refreshToken)}');
    }
    final res = await _raw(
      'POST',
      '/api/v1/token/refresh',
      body: {'refreshToken': refreshToken},
      auth: false,
    );
    final pair = TokenPair.fromJson(_decode(res));
    await onTokens?.call(pair); // persisted before anything uses it: a lost write would revoke the device on replay
    if (tracing(TraceArea.session)) {
      trace(
        TraceArea.session,
        'refresh: new #${await tokenTag(pair.refreshToken)} persisted',
      );
    }
    accessToken = pair.accessToken;
    refreshToken = pair.refreshToken;
    return pair;
  }

  Future<({AccountBundle bundle, int bundleVersion})> recoverStart({
    required String email,
    required List<int> recoveryAuthKey,
  }) async {
    final json = await _send(
      'POST',
      '/account/recover/start',
      body: {'email': email, 'recoveryAuthKey': b64(recoveryAuthKey)},
      auth: false,
    );
    if (json case {
      'bundle': final Object bundle,
      'bundleVersion': final int version,
    }) {
      return (bundle: AccountBundle.fromJson(bundle), bundleVersion: version);
    }
    throw const FormatException('recover/start: unexpected body');
  }

  Future<void> recover({
    required String email,
    required List<int> recoveryAuthKey,
    required AccountBundle bundle,
    required int bundleVersion,
    required List<int> authKey,
    required List<int> newRecoveryAuthKey,
  }) => _send(
    'POST',
    '/account/recover',
    body: {
      'email': email,
      'recoveryAuthKey': b64(recoveryAuthKey),
      'bundle': bundle.toJson(),
      'bundleVersion': bundleVersion,
      'authKey': b64(authKey),
      'newRecoveryAuthKey': b64(newRecoveryAuthKey),
    },
    auth: false,
  );

  Future<void> changeRecoveryKit({
    required List<int> currentAuthKey,
    required AccountBundle bundle,
    required int bundleVersion,
    required List<int> recoveryAuthKey,
  }) => _send(
    'POST',
    '/account/recovery-kit',
    body: {
      'currentAuthKey': b64(currentAuthKey),
      'bundle': bundle.toJson(),
      'bundleVersion': bundleVersion,
      'recoveryAuthKey': b64(recoveryAuthKey),
    },
  );

  Future<List<Device>> devices() async {
    final json = await _send('GET', '/devices');
    if (json case {'devices': final List<Object?> devices}) {
      return [for (final d in devices) Device.fromJson(d)];
    }
    throw const FormatException('devices: unexpected body');
  }

  Future<void> revokeDevice(String id) => _send('DELETE', '/devices/$id');

  Future<SyncPage> sync({required int cursor, int orgCursor = 0}) async =>
      SyncPage.fromJson(
        await _send(
          'GET',
          '/sync',
          query: {'cursor': '$cursor', 'orgCursor': '$orgCursor'},
        ),
      );

  Future<Item> putItem(Item item, {required int ifMatch}) async =>
      Item.fromJson(
        await _send(
          'PUT',
          '/items/${item.id}',
          body: item.toJson(),
          headers: {'if-match': '$ifMatch'},
        ),
      );

  /// One page of an audit view; [next] is the opaque cursor of the next page, null on the last one.
  Future<({List<AuditEvent> events, String? next})> audit({
    String scope = 'me',
    String? after,
    int limit = 100,
  }) async {
    final json = await _send(
      'GET',
      '/audit',
      query: {'scope': scope, 'after': ?after, 'limit': '$limit'},
    );
    if (json case {
      'events': final List<Object?> events,
      'next': final String? next,
    }) {
      return (
        events: [for (final e in events) AuditEvent.fromJson(e)],
        next: next,
      );
    }
    throw const FormatException('audit: unexpected body');
  }

  /// The current version first, then the older ones, newest first.
  Future<List<Item>> revisions(String itemId) async {
    final json = await _send('GET', '/items/$itemId/revisions');
    if (json case {'revisions': final List<Object?> revisions}) {
      return [for (final i in revisions) Item.fromJson(i)];
    }
    throw const FormatException('revisions: unexpected body');
  }

  Future<void> reportSsh({
    required String event,
    required String hostItemId,
    int? localPort,
    List<String> jumpHostItemIds = const [],
  }) => _send(
    'POST',
    '/events/ssh',
    body: {
      'event': event,
      'hostItemId': hostItemId,
      'localPort': ?localPort,
      if (jumpHostItemIds.isNotEmpty) 'jumpHostItemIds': jumpHostItemIds,
    },
  );

  Future<void> reportReveal(String itemId) =>
      _send('POST', '/events/reveal', body: {'itemId': itemId});

  Future<OrgRetention> orgRetention(String orgId) async {
    final json = await _send('GET', '/orgs/$orgId/settings/retention');
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
        server: (
          auditDays: auditDays,
          maxVersions: maxVersions,
          trashDays: trashDays,
        ),
        org: (
          auditDays: orgAuditDays,
          maxVersions: orgMaxVersions,
          trashDays: orgTrashDays,
        ),
      );
    }
    throw const FormatException('retention: unexpected body');
  }

  Future<({String id, String name, String role})> createOrg(String name) async {
    final json = await _send('POST', '/orgs', body: {'name': name});
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

  Future<void> updateOrg(
    String orgId, {
    String? name,
    Map<String, Object?>? settings,
  }) => _send(
    'PUT',
    '/orgs/$orgId',
    body: {'name': ?name, 'settings': ?settings},
  );

  Future<void> deleteOrg(String orgId) => _send('DELETE', '/orgs/$orgId');

  Future<void> setMemberRole(String orgId, String userId, OrgRole role) =>
      _send('PUT', '/orgs/$orgId/members/$userId', body: {'role': role.name});

  Future<void> removeMember(String orgId, String userId) =>
      _send('DELETE', '/orgs/$orgId/members/$userId');

  Future<void> confirmMember(String orgId, String userId) =>
      _send('POST', '/orgs/$orgId/members/$userId/confirm');

  Future<InviteCreated> createInvite(
    String orgId, {
    required String email,
    OrgRole role = OrgRole.member,
  }) async => InviteCreated.fromJson(
    await _send(
      'POST',
      '/orgs/$orgId/invites',
      body: {'email': email, 'role': role.name},
    ),
  );

  Future<List<PendingInvite>> orgInvites(String orgId) async =>
      _invites(await _send('GET', '/orgs/$orgId/invites'));

  Future<void> revokeInvite(String id) => _send('DELETE', '/invites/$id');

  /// Joins the org of an invite with the signed-in account; returns its id.
  Future<String> joinInvite(String token) async {
    final json = await _send('POST', '/invites/join', body: {'token': token});
    if (json case {'orgId': final String orgId}) return orgId;
    throw const FormatException('invites/join: unexpected body');
  }

  Future<OrgTeam> createTeam(
    String orgId, {
    required String name,
    List<String> memberIds = const [],
  }) async {
    final json = await _send(
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
  }) => _send(
    'PUT',
    '/orgs/$orgId/teams/$teamId',
    body: {'name': ?name, 'memberIds': ?memberIds},
  );

  Future<void> deleteTeam(String orgId, String teamId) =>
      _send('DELETE', '/orgs/$orgId/teams/$teamId');

  Future<void> putAcl(String folderId, List<AclEntry> entries) => _send(
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
  }) => _send(
    'PUT',
    '/folders/$folderId/keys',
    body: {
      'version': version,
      'wrapped': [for (final w in wrapped) w.toJson()],
      'history': history?.toJson(),
    },
  );

  Future<void> rotationDone(String folderId) =>
      _send('POST', '/folders/$folderId/rotation/done');

  Future<List<AdminUser>> adminUsers() async {
    final json = await _send('GET', '/admin/users');
    if (json case {'users': final List<Object?> users}) {
      return [for (final u in users) AdminUser.fromJson(u)];
    }
    throw const FormatException('admin/users: unexpected body');
  }

  Future<void> adminSetDisabled(String userId, bool disabled) =>
      _send('PUT', '/admin/users/$userId', body: {'disabled': disabled});

  Future<void> adminDeleteUser(String userId) =>
      _send('DELETE', '/admin/users/$userId');

  Future<List<AdminOrg>> adminOrgs() async {
    final json = await _send('GET', '/admin/orgs');
    if (json case {'orgs': final List<Object?> orgs}) {
      return [for (final o in orgs) AdminOrg.fromJson(o)];
    }
    throw const FormatException('admin/orgs: unexpected body');
  }

  Future<void> adminDeleteOrg(String orgId, String confirmName) =>
      _send('DELETE', '/admin/orgs/$orgId', body: {'confirmName': confirmName});

  Future<InviteCreated> adminInvite(String email) async =>
      InviteCreated.fromJson(
        await _send('POST', '/admin/invites', body: {'email': email}),
      );

  Future<List<PendingInvite>> adminInvites() async =>
      _invites(await _send('GET', '/admin/invites'));

  static List<PendingInvite> _invites(Object? json) {
    if (json case {'invites': final List<Object?> invites}) {
      return [for (final i in invites) PendingInvite.fromJson(i)];
    }
    throw const FormatException('invites: unexpected body');
  }

  /// `GET /api/info` with the token. A public answer while signed in (a refresh token held; right after
  /// an unlock there is no access token yet) means the token is stale or missing: refresh once and ask
  /// again. The second answer is final.
  Future<ApiInfo> info() async {
    var info = ApiInfo.fromJson(
      _decode(await _raw('GET', '/api/info', auth: true)),
    );
    if (info.server == null && refreshToken != null) {
      await _refreshOnce();
      info = ApiInfo.fromJson(
        _decode(await _raw('GET', '/api/info', auth: true)),
      );
    }
    return info;
  }

  /// Writes an outdated or incompatible client may still make: reading, signing in, protecting the account.
  static bool _allowedReadOnly(String method, String path) =>
      method == 'GET' ||
      (method == 'DELETE' && path.startsWith('/devices/')) ||
      path == '/prelogin' ||
      path == '/login' ||
      path == '/token/refresh' ||
      path == '/account/password' ||
      path.startsWith('/events/');

  Future<TokenPair>? _refreshing;

  Future<TokenPair> _refreshOnce() =>
      _refreshing ??= refresh().whenComplete(() => _refreshing = null);

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String> headers = const {},
    bool auth = true,
  }) async {
    if (readOnly && !_allowedReadOnly(method, path)) {
      throw const ReadOnlyException();
    }
    var busy = 0; // short 429s (server busy, e.g. the Argon2 queue full): retried silently
    var refreshed = false;
    while (true) {
      final sentWith = accessToken;
      final res = await _raw(
        method,
        '/api/v1$path',
        body: body,
        query: query,
        headers: headers,
        auth: auth,
      );
      final after = int.tryParse(res.headers['retry-after'] ?? '');
      if (res.statusCode == 429 && after != null && after <= 2 && busy < 5) {
        busy++;
        await sleep(Duration(seconds: after));
        continue;
      }
      if (res.statusCode == 401 && auth && !refreshed && refreshToken != null) {
        final reason = _reasonOf(res);
        if (reason == null || reason == UnauthorizedReason.invalidToken.wire) {
          // another call already rotated the token while this one was in flight: retry with it
          if (accessToken == sentWith) await _refreshOnce();
          refreshed = true;
          continue;
        }
      }
      return _decode(res);
    }
  }

  Future<Session> _session(String path, Map<String, Object?> body) async {
    final session = Session.fromJson(
      await _send('POST', path, body: body, auth: false),
    );
    await onTokens?.call(TokenPair(session.accessToken, session.refreshToken));
    accessToken = session.accessToken;
    refreshToken = session.refreshToken;
    return session;
  }

  Future<http.Response> _raw(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String> headers = const {},
    required bool auth,
  }) async {
    final request =
        http.Request(
            method,
            baseUrl.replace(path: path, queryParameters: query),
          )
          ..headers.addAll({
            'content-type': 'application/json',
            if (path.startsWith('/api/v1/')) 'x-unfeudal-client': clientVersion,
            if (auth && accessToken != null)
              'authorization': 'Bearer $accessToken',
            ...headers,
          });
    if (body != null) request.body = jsonEncode(body);
    final watch = Stopwatch()..start();
    try {
      final res = await http.Response.fromStream(
        await _http.send(request).timeout(_timeout),
      );
      trace(
        TraceArea.http,
        '$method $path → ${res.statusCode} (${watch.elapsedMilliseconds} ms)',
      );
      return res;
    } on http.ClientException catch (e) {
      trace(TraceArea.http, '$method $path → network error');
      throw NetworkException(e);
    } on IOException catch (e) {
      trace(TraceArea.http, '$method $path → network error');
      throw NetworkException(e);
    } on TimeoutException catch (e) {
      trace(TraceArea.http, '$method $path → timeout');
      throw NetworkException(e);
    }
  }

  /// 2xx: the JSON body, null when empty. Else an [ApiException]; a body that is not JSON is a [FormatException].
  static Object? _decode(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.body.isEmpty ? null : jsonDecode(res.body);
    }
    final error = ApiErrorBody.fromJson(jsonDecode(res.body));
    final after = int.tryParse(res.headers['retry-after'] ?? '');
    return throw ApiException(
      error.error,
      res.statusCode,
      message: error.message,
      reason: error.reason,
      item: error.item,
      orgs: (error.extra['orgs'] as List<Object?>?)?.cast<String>(),
      retryAfter: after == null ? null : Duration(seconds: after),
    );
  }

  static String? _reasonOf(http.Response res) {
    try {
      return ApiErrorBody.fromJson(jsonDecode(res.body)).reason;
    } on FormatException {
      return null;
    }
  }

  static Map<String, String> _device(DeviceInput d) => {
    'name': d.name,
    'platform': d.platform,
  };
}
