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

part 'admin_api.dart';
part 'api_errors.dart';
part 'org_api.dart';

class ApiClient {
  ApiClient(this.baseUrl, this._http);

  final Uri baseUrl;
  final http.Client _http;
  late final orgs = OrgApi._(this);
  late final admin = AdminApi._(this);
  String? accessToken;
  String? refreshToken;

  /// Must persist the new pair before it resolves: a lost refresh token revokes the device on replay.
  Future<void> Function(TokenPair)? onTokens;
  bool Function() isReadOnly = () => false;
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
    if (isTracing(TraceArea.session)) {
      trace(TraceArea.session, 'refresh with #${await tokenTag(refreshToken)}');
    }
    final res = await _raw(
      'POST',
      '/api/v1/token/refresh',
      body: {'refreshToken': refreshToken},
      auth: false,
    );
    final pair = TokenPair.fromJson(_decode(res));
    // Persisted before anything uses it: a lost write would revoke the device on replay.
    await onTokens?.call(pair);
    if (isTracing(TraceArea.session)) {
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

  /// Every other device of the account is signed out by the server.
  Future<void> changePassword({
    required List<int> currentAuthKey,
    required AccountBundle bundle,
    required int bundleVersion,
    required List<int> authKey,
  }) => _send(
    'POST',
    '/account/password',
    body: {
      'currentAuthKey': b64(currentAuthKey),
      'bundle': bundle.toJson(),
      'bundleVersion': bundleVersion,
      'authKey': b64(authKey),
    },
  );

  Future<void> deleteAccount({required List<int> currentAuthKey}) => _send(
    'DELETE',
    '/account',
    body: {'currentAuthKey': b64(currentAuthKey)},
  );

  /// The language of the security mails.
  Future<void> setLocale(String locale) =>
      _send('PUT', '/account/locale', body: {'locale': locale});

  Future<List<Device>> devices() =>
      _list('/devices', 'devices', Device.fromJson);

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

  /// One page of an audit view; `next` is the opaque cursor of the next page, null on the last one.
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
  Future<List<Item>> revisions(String itemId) =>
      _list('/items/$itemId/revisions', 'revisions', Item.fromJson);

  Future<void> reportSsh({
    required SshEvent event,
    required String hostItemId,
    int? localPort,
    List<String> jumpHostItemIds = const [],
  }) => _send(
    'POST',
    '/events/ssh',
    body: {
      'event': event.wire,
      'hostItemId': hostItemId,
      'localPort': ?localPort,
      if (jumpHostItemIds.isNotEmpty) 'jumpHostItemIds': jumpHostItemIds,
    },
  );

  Future<void> reportReveal(String itemId) =>
      _send('POST', '/events/reveal', body: {'itemId': itemId});

  /// GET [path], then the list under [key].
  Future<List<T>> _list<T>(
    String path,
    String key,
    T Function(Object?) from,
  ) async {
    final json = await _send('GET', path);
    if (json is Map ? json[key] : null case final List<Object?> list) {
      return [for (final e in list) from(e)];
    }
    throw FormatException('$key: unexpected body');
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

  // Writes an outdated or incompatible client may still make: reading, signing in, protecting the account.
  static bool _allowedReadOnly(String method, String path) =>
      method == 'GET' ||
      (method == 'DELETE' && path.startsWith('/devices/')) ||
      path == '/prelogin' ||
      path == '/login' ||
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
    if (isReadOnly() && !_allowedReadOnly(method, path)) {
      throw const ReadOnlyException();
    }
    // Short 429s (server busy, e.g. the Argon2 queue full) are retried silently.
    var busy = 0;
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
        '$method $path -> ${res.statusCode} (${watch.elapsedMilliseconds} ms)',
      );
      return res;
    } on Exception catch (e) {
      if (e is! http.ClientException &&
          e is! IOException &&
          e is! TimeoutException) {
        rethrow;
      }
      final what = e is TimeoutException ? 'timeout' : 'network error';
      trace(TraceArea.http, '$method $path -> $what');
      throw NetworkException(e);
    }
  }

  static Map<String, String> _device(DeviceInput d) => {
    'name': d.name,
    'platform': d.platform,
  };
}
