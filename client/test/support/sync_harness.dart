// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:unfeudal_client/src/api/api_client.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/sync/sync_engine.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'fakes.dart';

class HarnessAccount {
  HarnessAccount(
    this.userId,
    this.email,
    this.bundle,
    this.authKey,
    this.recoveryAuthKey, {
    this.account,
    this.isOwner = false,
  });
  final String userId, email;
  final NewAccount? account; // keys for tests
  final bool isOwner;
  AccountBundle bundle;
  int bundleVersion = 0;
  String authKey, recoveryAuthKey;
}

class HarnessDevice {
  HarnessDevice(this.id, this.userId, this.name, this.platform);
  final String id, userId, name, platform;
  String access = '', refresh = '';
  final used = <String>{};
  DateTime? revokedAt;
  bool expired = false;
}

typedef HarnessLogin = ({
  HarnessAccount account,
  String deviceId,
  String accessToken,
  String refreshToken,
});
typedef HarnessSnapshot = ({
  Map<String, (Item, String, int)> items,
  int itemsSeq,
});

/// In-memory server speaking the HTTP API over `http.MockClient`.
class SyncHarness {
  SyncHarness({
    this.minClient = '0.1.0',
    this.latestClient = '0.1.0',
    this.api = const [1],
    this.capabilities = const ['mascot', 'recovery_kit', 'reveal', 'sync'],
    this.infoExtra = const {},
    this.pageSize = 500,
    Uri? baseUrl,
  }) : baseUrl = baseUrl ?? Uri.parse('https://vault.test');

  final Uri baseUrl;
  String minClient, latestClient;
  List<int> api;
  List<String> capabilities;
  Map<String, Object?> infoExtra;
  int pageSize;
  String? instanceEpoch = 'q83vEjRWeJCrze8SNFZ4kA';
  String setupToken = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  bool offline = false;
  DateTime now = DateTime.utc(2026, 10, 15, 12);
  final failPuts = <String, int>{};
  final requests = <String>[];
  final accounts = <String, HarnessAccount>{};
  final devices = <String, HarnessDevice>{};
  final invites = <String, String>{}; // token → email
  void Function(String itemId)?
  onPut; // runs when a PUT arrives, before it is applied
  OrgBlock? orgBlock;
  final orgCalls =
      <
        ({String route, Map<String, Object?> body})
      >[]; // every org, invite-join, folder and admin call
  final orgReplies =
      <
        String,
        http.Response Function(Map<String, Object?> body)
      >{}; // 'PUT /folders/<id>/keys' → answer
  final orgMembers =
      <
        String,
        Set<String>
      >{}; // orgId → userIds who read (sync) and write that org's items
  String? syncBodyOverride; // raw 200 body for malformed answers
  int itemsSeq = 0;
  final _items = <String, (Item, String, int)>{}; // id → (item, owner, seq)
  int _n = 0;

  late final http.Client client = MockClient(_handle);

  Future<HarnessAccount> createAccount(
    String email,
    String password, {
    bool owner = false,
  }) async {
    final acc = await AccountCrypto(
      kdf: KdfParams.testing,
      allowTestingKdf: true,
    ).create(password);
    return accounts[email] = HarnessAccount(
      newId(),
      email,
      acc.bundle,
      b64(acc.authKey),
      b64(acc.recoveryAuthKey),
      account: acc,
      isOwner: owner || accounts.isEmpty,
    );
  }

  Future<HarnessLogin> signIn({
    String email = 'camille@example.org',
    String password = 'password-123',
  }) async {
    final a = accounts[email] ?? await createAccount(email, password);
    final d = _newDevice(a, 'Windows', 'windows');
    return (
      account: a,
      deviceId: d.id,
      accessToken: d.access,
      refreshToken: d.refresh,
    );
  }

  /// A signed-in engine over a fresh in-memory mirror; conflict copies are recorded in [copies].
  Future<(SyncEngine, LocalMirror, HarnessLogin)> engine({
    List<Item>? copies,
    DateTime Function()? now,
  }) async {
    final login = await signIn();
    final api = ApiClient(baseUrl, client)
      ..accessToken = login.accessToken
      ..refreshToken = login.refreshToken;
    final mirror = LocalMirror.inMemory();
    final e =
        SyncEngine(
            api: api,
            mirror: mirror,
            deviceId: login.deviceId,
            now: now ?? DateTime.now,
          )
          ..copyOf = (mine, {required personal}) async {
            final c = wireItem(newId(), revision: 0, type: mine.type);
            copies?.add(c);
            return c;
          };
    return (e, mirror, login);
  }

  Item? serverItem(String id) => _items[id]?.$1;
  List<Item> get serverItems => [for (final e in _items.values) e.$1];

  /// Another device of [email] (or [deviceId]) writes [item].
  Item serverPut(
    Item item, {
    String email = 'camille@example.org',
    String? deviceId,
  }) {
    final a = accounts[email]!;
    return _store(
      item,
      (serverItem(item.id)?.revision ?? 0) + 1,
      a.userId,
      deviceId ?? newId(),
    );
  }

  static http.Response reply(Object? body, [int status = 200]) =>
      _json(body, status);

  /// Another member writes an org item.
  Item serverPutOrg(Item item, {String? userId}) => _store(
    item,
    (serverItem(item.id)?.revision ?? 0) + 1,
    'org:${item.orgId}',
    newId(),
    by: userId ?? newId(),
  );

  void purge(String id) {
    final (item, owner, _) = _items[id]!;
    final j = item.toJson()
      ..['deleted'] = true
      ..['purged'] = true
      ..['meta'] = null
      ..['secret'] = null;
    _items[id] = (Item.fromJson(j), owner, ++itemsSeq);
  }

  /// Hostile server: serves [earlier] again as the newest change, revision untouched.
  void serveOlder(Item earlier) =>
      _items[earlier.id] = (earlier, _items[earlier.id]!.$2, ++itemsSeq);

  HarnessSnapshot snapshot() => (items: Map.of(_items), itemsSeq: itemsSeq);

  /// Restore from a backup: items and seq go back; [epoch] is the new instance epoch (null = missing).
  void restore(HarnessSnapshot s, {String? epoch}) {
    _items
      ..clear()
      ..addAll(s.items);
    itemsSeq = s.itemsSeq;
    instanceEpoch = epoch;
  }

  void expireAccess() {
    for (final d in devices.values) {
      d.access = 'expired-${d.access}';
    }
  }

  void expireSessions() {
    expireAccess();
    for (final d in devices.values) {
      d.expired = true;
    }
  }

  HarnessDevice _newDevice(HarnessAccount a, String name, String platform) {
    final d = HarnessDevice(newId(), a.userId, name, platform);
    _rotate(d);
    return devices[d.id] = d;
  }

  void _rotate(HarnessDevice d) {
    d.access = 'access.${++_n}';
    d.refresh = 'refresh-${++_n}';
  }

  Item _store(
    Item body,
    int revision,
    String owner,
    String deviceId, {
    String? by,
    Envelope? keepSecret,
  }) {
    final j = body.toJson()
      ..remove('purged')
      ..['revision'] = revision
      ..['createdAt'] =
          iso(
            _items[body.id]?.$1.createdAt ?? now,
          ) // set on insert, kept on update
      ..['updatedAt'] = iso(now)
      ..['updatedBy'] = by ?? owner
      ..['updatedDevice'] = deviceId;
    if (j['secret'] == null && keepSecret != null) {
      j['secret'] = keepSecret.toJson();
    }
    final stored = Item.fromJson(j);
    _items[body.id] = (stored, owner, ++itemsSeq);
    return stored;
  }

  Map<String, Object?> _session(HarnessAccount a, HarnessDevice d) => {
    'userId': a.userId,
    'deviceId': d.id,
    'accessToken': d.access,
    'refreshToken': d.refresh,
    'bundle': a.bundle.toJson(),
    'bundleVersion': a.bundleVersion,
    'isInstanceOwner': a.isOwner,
  };

  HarnessDevice? _caller(http.Request r) {
    final auth = r.headers['authorization'];
    return devices.values
        .where((d) => auth == 'Bearer ${d.access}')
        .firstOrNull;
  }

  Map<String, Object?> _info(HarnessDevice? d) {
    const public = {'sync', 'recovery_kit', 'plain_http_lan', 'mascot'};
    final full = d != null && d.revokedAt == null;
    final caps = [...capabilities]..sort();
    return {
      'api': api,
      'minClient': minClient,
      'latestClient': latestClient,
      'capabilities': full
          ? caps
          : [
              for (final c in caps)
                if (public.contains(c)) c,
            ],
      if (full) 'server': '0.1.0',
      if (full && instanceEpoch != null) 'instanceEpoch': instanceEpoch,
      if (full) ...{'source': 'https://example.org/src', 'trashDays': 30},
      ...infoExtra,
    };
  }

  Future<http.Response> _handle(http.Request r) async {
    final path = r.url.path;
    requests.add('${r.method} $path');
    if (offline) throw http.ClientException('offline', r.url);
    if (path == '/api/info') return _json(_info(_caller(r)));
    if (!path.startsWith('/api/v1/')) return _error(404, 'not_found');
    final v = r.headers['x-unfeudal-client'];
    if (v == null || !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(v)) {
      return _error(400, 'invalid_request');
    }
    final route = '${r.method} ${path.substring(7)}';
    const exempt = {
      'POST /prelogin',
      'POST /login',
      'POST /token/refresh',
      'POST /account/password',
    };
    if (r.method != 'GET' &&
        compareVersions(v, minClient) < 0 &&
        !exempt.contains(route) &&
        !route.startsWith('DELETE /devices/')) {
      return _error(409, 'conflict', {'reason': 'client_too_old'});
    }
    final body = r.body.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(r.body) as Map<String, Object?>;
    String? s(String k) => body[k] as String?;
    ({String name, String platform})? device() {
      final d = body['device'];
      if (d is! Map ||
          d['name'] is! String ||
          !devicePlatforms.contains(d['platform'])) {
        return null;
      }
      return (name: d['name'] as String, platform: d['platform'] as String);
    }

    switch (route) {
      case 'POST /setup':
        if (accounts.isNotEmpty) return _error(409, 'setup_done');
        final dev = device();
        if (dev == null) return _error(400, 'invalid_request');
        if (normalizeSetupToken(s('token') ?? '') != setupToken) {
          return _error(401, 'unauthorized');
        }
        final a = accounts[s('email')!] = HarnessAccount(
          newId(),
          s('email')!,
          AccountBundle.fromJson(body['bundle']),
          s('authKey')!,
          s('recoveryAuthKey')!,
          isOwner: true,
        );
        return _json(_session(a, _newDevice(a, dev.name, dev.platform)), 201);
      case 'POST /invites/accept':
        if (invites[s('token')] != s('email')) return _error(404, 'not_found');
        if (accounts.containsKey(s('email'))) {
          return _error(409, 'conflict', {'reason': 'account_exists'});
        }
        final dev = device()!;
        final a = accounts[s('email')!] = HarnessAccount(
          newId(),
          s('email')!,
          AccountBundle.fromJson(body['bundle']),
          s('authKey')!,
          s('recoveryAuthKey')!,
        );
        invites.remove(s('token'));
        return _json(_session(a, _newDevice(a, dev.name, dev.platform)), 201);
      case 'POST /prelogin':
        final a = accounts[s('email')];
        return _json({
          'salt': b64(a?.bundle.salt ?? List.filled(16, 1)),
          'kdf': (a?.bundle.kdf ?? KdfParams.defaults).toJson(),
        });
      case 'POST /login':
        final a = accounts[s('email')];
        final dev = device();
        if (dev == null) return _error(400, 'invalid_request');
        if (a == null || a.authKey != s('authKey')) {
          return _error(401, 'unauthorized');
        }
        return _json(_session(a, _newDevice(a, dev.name, dev.platform)));
      case 'POST /token/refresh':
        final token = s('refreshToken');
        final replayed = devices.values
            .where((d) => d.used.contains(token))
            .firstOrNull;
        if (replayed != null) {
          replayed.revokedAt = now;
          return _error(401, 'unauthorized', {'reason': 'device_revoked'});
        }
        final d = devices.values.where((d) => d.refresh == token).firstOrNull;
        if (d == null) {
          return _error(401, 'unauthorized', {'reason': 'invalid_token'});
        }
        if (d.revokedAt != null) {
          return _error(401, 'unauthorized', {'reason': 'device_revoked'});
        }
        if (d.expired) {
          return _error(401, 'unauthorized', {'reason': 'session_expired'});
        }
        d.used.add(d.refresh);
        _rotate(d);
        return _json({'accessToken': d.access, 'refreshToken': d.refresh});
      case 'POST /account/recover/start':
        final a = accounts[s('email')];
        if (a == null || a.recoveryAuthKey != s('recoveryAuthKey')) {
          return _error(401, 'unauthorized');
        }
        return _json({
          'bundle': a.bundle.toJson(),
          'bundleVersion': a.bundleVersion,
        });
      case 'POST /account/recover':
        final a = accounts[s('email')];
        if (a == null || a.recoveryAuthKey != s('recoveryAuthKey')) {
          return _error(401, 'unauthorized');
        }
        if (body['bundleVersion'] != a.bundleVersion) {
          return _error(409, 'conflict');
        }
        a
          ..bundle = AccountBundle.fromJson(body['bundle'])
          ..bundleVersion += 1
          ..authKey = s('authKey')!
          ..recoveryAuthKey = s('newRecoveryAuthKey')!;
        for (final d in devices.values.where((d) => d.userId == a.userId)) {
          d.revokedAt ??= now;
        }
        return http.Response('', 204);
    }

    final me = _caller(r);
    if (me == null) {
      return _error(401, 'unauthorized', {'reason': 'invalid_token'});
    }
    if (me.revokedAt != null) {
      return _error(401, 'unauthorized', {'reason': 'device_revoked'});
    }
    final account = accounts.values.firstWhere((a) => a.userId == me.userId);

    if (route == 'GET /devices') {
      return _json({
        'devices': [
          for (final d in devices.values.where((d) => d.userId == me.userId))
            Device.fromJson({
              'id': d.id,
              'name': d.name,
              'platform': d.platform,
              'createdAt': iso(now),
              'lastSeenAt': iso(now),
              'revokedAt': d.revokedAt == null ? null : iso(d.revokedAt!),
              'current': d.id == me.id,
            }).toJson(),
        ],
      });
    }
    if (route.startsWith('DELETE /devices/')) {
      final d = devices[path.split('/').last];
      if (d == null || d.userId != me.userId) return _error(404, 'not_found');
      d.revokedAt ??= now;
      return http.Response('', 204);
    }
    if (route == 'POST /account/recovery-kit') {
      if (s('currentAuthKey') != account.authKey) {
        return _error(403, 'forbidden');
      }
      if (body['bundleVersion'] != account.bundleVersion) {
        return _error(409, 'conflict');
      }
      account
        ..bundle = AccountBundle.fromJson(body['bundle'])
        ..bundleVersion += 1
        ..recoveryAuthKey = s('recoveryAuthKey')!;
      return http.Response('', 204);
    }
    if (route == 'GET /sync') {
      final cursor = int.parse(r.url.queryParameters['cursor'] ?? '0');
      final orgCursor = int.parse(r.url.queryParameters['orgCursor'] ?? '0');
      if (cursor > itemsSeq) {
        return _error(409, 'conflict', {'reason': 'cursor_ahead'});
      }
      if (syncBodyOverride != null) {
        return http.Response(syncBodyOverride!, 200, headers: _jsonHeaders);
      }
      final mine =
          _items.values
              .where((e) => e.$2 == me.userId || _readsOrg(me.userId, e.$2))
              .where((e) => e.$3 > cursor)
              .toList()
            ..sort((a, b) => a.$3.compareTo(b.$3));
      final page = mine.take(pageSize).toList();
      return _json({
        'items': [for (final e in page) e.$1.toJson()],
        'cursor': page.isEmpty ? cursor : page.last.$3,
        'more': mine.length > page.length,
        if (orgBlock != null && orgBlock!.orgCursor > orgCursor)
          'org': orgBlock!.toJson(),
      });
    }
    if (r.method == 'PUT' && path.startsWith('/api/v1/items/')) {
      final id = path.split('/').last;
      final m = RegExp(r'^\s*"?(\d{1,15})"?\s*$')
          .firstMatch(r.headers['if-match'] ?? '');
      if (!isUuid(id) || m == null) return _error(400, 'invalid_request');
      onPut?.call(id);
      if (failPuts[id] case final status?) {
        return _error(
          status,
          _codeFor(status),
          null,
          status == 429 ? {'retry-after': '7'} : null,
        );
      }
      final input = Item.fromJson({...body, 'id': id});
      final owner = input.scope == ItemScope.org
          ? 'org:${input.orgId}'
          : me.userId;
      if (input.scope == ItemScope.org &&
          !(orgMembers[input.orgId]?.contains(me.userId) ?? false)) {
        return _error(404, 'not_found');
      }
      final current = _items[id];
      if (current != null && current.$1.purged) {
        return _json({
          'error': 'conflict',
          'message': '',
          'item': current.$1.toJson(),
        }, 409);
      }
      if (current != null && current.$2 != owner) {
        return _error(403, 'forbidden');
      }
      if (current != null && current.$1.type != input.type) {
        return _error(400, 'invalid_request');
      }
      if (current != null &&
          current.$1.secret != null &&
          input.secret == null &&
          current.$1.folderId != input.folderId) {
        return _error(400, 'invalid_request');
      }
      if (int.parse(m[1]!) != (current?.$1.revision ?? 0)) {
        return _json({
          'error': 'conflict',
          'message': '',
          'item': current?.$1.toJson(),
        }, 409);
      }
      return _json(
        _store(
          input,
          (current?.$1.revision ?? 0) + 1,
          owner,
          me.id,
          by: me.userId,
          keepSecret: current?.$1.secret,
        ).toJson(),
      );
    }
    final orgRoute =
        RegExp(r'^/api/v1/(orgs|folders|admin)(/|$)').hasMatch(path) ||
        route == 'POST /invites/join' ||
        (r.method == 'DELETE' && path.startsWith('/api/v1/invites/'));
    if (orgRoute) {
      orgCalls.add((route: route, body: body));
      return orgReplies[route]?.call(body) ?? http.Response('', 204);
    }
    return _error(404, 'not_found');
  }

  bool _readsOrg(String userId, String owner) =>
      owner.startsWith('org:') &&
      (orgMembers[owner.substring(4)]?.contains(userId) ?? false);

  static const _jsonHeaders = {
    'content-type': 'application/json; charset=utf-8',
  };
  static http.Response _json(Object? body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: _jsonHeaders);
  static http.Response _error(
    int status,
    String code, [
    Map<String, Object?>? extra,
    Map<String, String>? headers,
  ]) => http.Response(
    jsonEncode({'error': code, 'message': code, ...?extra}),
    status,
    headers: {..._jsonHeaders, ...?headers},
  );
  static String _codeFor(int status) => switch (status) {
    400 => 'invalid_request',
    403 => 'forbidden',
    404 => 'not_found',
    413 => 'payload_too_large',
    429 => 'rate_limited',
    _ => 'internal',
  };
}
