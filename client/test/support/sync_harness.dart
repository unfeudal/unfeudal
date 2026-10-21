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
  HarnessAccount({
    required this.userId,
    required this.email,
    required this.bundle,
    required this.authKey,
    required this.recoveryAuthKey,
    this.account,
    this.isOwner = false,
  });
  final String userId, email;
  final NewAccount? account; // keys for tests
  final bool isOwner;
  AccountBundle bundle;
  String locale = 'en';
  List<String> lastOwnerOf = [];
  int bundleVersion = 0;
  String authKey, recoveryAuthKey;
}

class HarnessDevice {
  HarnessDevice({
    required this.id,
    required this.userId,
    required this.name,
    required this.platform,
  });
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

  /// While set, GET /api/info waits for it.
  Future<void>? holdInfo;
  DateTime now = DateTime.utc(2026, 10, 15, 12);
  final failPuts = <String, int>{};

  /// PUT /items/{id} of these ids never reaches the server: a network error.
  final dropPuts = <String>{};
  final requests = <String>[];
  final hosts = <String>{};
  final accounts = <String, HarnessAccount>{};
  final devices = <String, HarnessDevice>{};

  /// Invite token to email.
  final invites = <String, String>{};

  /// Runs when a PUT arrives, before it is applied.
  void Function(String itemId)? onPut;
  OrgBlock? orgBlock;

  /// Every org, invite-join, folder and admin call.
  final orgCalls = <({String route, Map<String, Object?> body})>[];

  /// Route such as `PUT /folders/<id>/keys` to its answer.
  final orgReplies =
      <String, http.Response Function(Map<String, Object?> body)>{};

  /// Org id to the user ids who read (sync) and write that org's items.
  final orgMembers = <String, Set<String>>{};

  /// Every scope; GET /audit filters it like the server.
  final auditLog = <AuditEvent>[];
  final _auditHeads = <String, (int, String)>{};

  /// Accepted events.
  final reported = <({String route, Map<String, Object?> body})>[];

  /// Answers events with this error status instead.
  int? eventStatus;

  /// Older versions, newest first, filled by _store.
  final revisionsOf = <String, List<Item>>{};

  /// Org id to its GET .../settings/retention body.
  final retention = <String, Map<String, Object?>>{};

  /// Raw 200 body for malformed answers.
  String? syncBodyOverride;
  int itemsSeq = 0;
  // Item id to (item, owner, seq).
  final _items = <String, (Item, String, int)>{};
  int _n = 0;

  late final http.Client client = MockClient(_handle);

  Future<HarnessAccount> createAccount(
    String email,
    String password, {
    bool owner = false,
  }) async {
    final acc = await AccountCrypto(
      kdf: KdfParams.testing,
      kdfFloor: KdfParams.testing,
    ).create(password);
    return accounts[email] = HarnessAccount(
      userId: newId(),
      email: email,
      bundle: acc.bundle,
      authKey: b64(acc.authKey),
      recoveryAuthKey: b64(acc.recoveryAuthKey),
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

  /// Appends a valid event to [scope]'s chain; ts = now + 1 s per event.
  AuditEvent appendAudit(
    String scope,
    String action, {
    List<String> targets = const [],
    String? actorUser,
    String? ipAddress,
  }) {
    final (seq, prev) = _auditHeads[scope] ?? (0, genesisHash);
    final fields = <String, Object?>{
      'scope': scope,
      'seq': seq + 1,
      'ts': iso(now.add(Duration(seconds: auditLog.length))),
      'actorUser': actorUser,
      'actorDevice': null,
      'ip': null,
      'action': action,
      'targetIds': targets,
    };
    final e = AuditEvent.fromJson({
      ...fields,
      'prevHash': prev,
      'hash': auditHash(prev, fields),
      'ipAddress': ?ipAddress,
    });
    auditLog.add(e);
    _auditHeads[scope] = (e.seq, e.hash);
    return e;
  }

  /// Hostile server: rewrites event [seq] of [scope] and re-links the rest, so the chain verifies again.
  void rewriteAudit(String scope, int seq, String action) {
    final chain = auditLog.where((e) => e.scope == scope).toList();
    auditLog.removeWhere((e) => e.scope == scope);
    var prev = chain.first.prevHash;
    for (final e in chain) {
      final fields = {...e.hashFields(), if (e.seq == seq) 'action': action};
      final next = AuditEvent.fromJson({
        ...fields,
        'prevHash': prev,
        'hash': auditHash(prev, fields),
      });
      auditLog.add(next);
      prev = next.hash;
    }
    _auditHeads[scope] = (chain.last.seq, prev);
  }

  /// Retention: drops events up to [upTo] and appends the checkpoint naming it.
  void purgeAudit(String scope, int upTo) {
    final last = auditLog.firstWhere((e) => e.scope == scope && e.seq == upTo);
    auditLog.removeWhere((e) => e.scope == scope && e.seq <= upTo);
    appendAudit(
      scope,
      'audit.checkpoint',
      targets: ['seq:$upTo', 'hash:${last.hash}'],
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
    final d = HarnessDevice(
      id: newId(),
      userId: a.userId,
      name: name,
      platform: platform,
    );
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
    // createdAt is set on insert and kept on update.
    final j = body.toJson()
      ..remove('purged')
      ..['revision'] = revision
      ..['createdAt'] = iso(_items[body.id]?.$1.createdAt ?? now)
      ..['updatedAt'] = iso(now)
      ..['updatedBy'] = by ?? owner
      ..['updatedDevice'] = deviceId;
    if (j['secret'] == null && keepSecret != null) {
      j['secret'] = keepSecret.toJson();
    }
    final stored = Item.fromJson(j);
    if (_items[body.id] case (final prev, _, _)) {
      (revisionsOf[body.id] ??= []).insert(0, prev);
    }
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
    hosts.add(r.url.host);
    final path = r.url.path;
    requests.add('${r.method} $path');
    if (offline) throw http.ClientException('offline', r.url);
    if (r.method == 'PUT' &&
        dropPuts.any((id) => path == '/api/v1/items/$id')) {
      throw http.ClientException('dropped', r.url);
    }
    if (path == '/api/info') {
      await holdInfo;
      return _json(_info(_caller(r)));
    }
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
          userId: newId(),
          email: s('email')!,
          bundle: AccountBundle.fromJson(body['bundle']),
          authKey: s('authKey')!,
          recoveryAuthKey: s('recoveryAuthKey')!,
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
          userId: newId(),
          email: s('email')!,
          bundle: AccountBundle.fromJson(body['bundle']),
          authKey: s('authKey')!,
          recoveryAuthKey: s('recoveryAuthKey')!,
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
    if (route == 'POST /account/password') {
      if (s('currentAuthKey') != account.authKey) {
        return _error(403, 'forbidden');
      }
      if (body['bundleVersion'] != account.bundleVersion) {
        return _error(409, 'conflict');
      }
      account
        ..bundle = AccountBundle.fromJson(body['bundle'])
        ..bundleVersion += 1
        ..authKey = s('authKey')!;
      for (final d in devices.values.where(
        (d) => d.userId == me.userId && d.id != me.id,
      )) {
        d.revokedAt ??= now;
      }
      return http.Response('', 204);
    }
    if (route == 'DELETE /account') {
      if (account.isOwner || s('currentAuthKey') != account.authKey) {
        return _error(403, 'forbidden');
      }
      if (account.lastOwnerOf.isNotEmpty) {
        return _error(409, 'conflict', {
          'reason': 'last_owner',
          'orgs': [...account.lastOwnerOf]..sort(),
        });
      }
      accounts.remove(account.email);
      devices.removeWhere((_, d) => d.userId == me.userId);
      _items.removeWhere((_, e) => e.$2 == me.userId);
      return http.Response('', 204);
    }
    if (route == 'PUT /account/locale') {
      if (body['locale'] != 'en' && body['locale'] != 'fr') {
        return _error(400, 'invalid_request');
      }
      account.locale = body['locale']! as String;
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
    if (route == 'GET /audit') {
      final q = r.url.queryParameters;
      final scope = q['scope'] ?? 'me';
      final limit = int.parse(q['limit'] ?? '100');
      final chain = scope != 'me' && !scope.startsWith('folder:');
      bool inView(AuditEvent e) => scope == 'me'
          ? e.actorUser == me.userId
          : scope.startsWith('folder:')
          ? e.targetIds.contains(scope.substring(7))
          : e.scope == (scope == 'user' ? 'user:${me.userId}' : scope);
      int cmp(AuditEvent e, AuditCursor c) => chain
          ? e.seq.compareTo(c.q)
          : [
              e.ts.compareTo(c.t),
              e.scope.compareTo(c.s),
              e.seq.compareTo(c.q),
            ].firstWhere((x) => x != 0, orElse: () => 0);
      final all = auditLog.where(inView).toList()
        ..sort((a, b) => cmp(a, AuditCursor(t: b.ts, s: b.scope, q: b.seq)));
      final after = q['after'] == null ? null : AuditCursor.decode(q['after']!);
      final rest = [
        for (final e in all)
          if (after == null || cmp(e, after) > 0) e,
      ];
      final page = rest.take(limit).toList();
      return _json({
        'events': [for (final e in page) e.toJson()],
        'next': rest.length > limit
            ? AuditCursor(
                t: page.last.ts,
                s: page.last.scope,
                q: page.last.seq,
              ).encode()
            : null,
      });
    }
    if (route == 'POST /events/ssh' || route == 'POST /events/reveal') {
      if (eventStatus case final status?) {
        return _error(status, _codeFor(status));
      }
      reported.add((route: route, body: body));
      return http.Response('', 204);
    }
    if (r.method == 'GET' &&
        RegExp(r'^/api/v1/items/[^/]+/revisions$').hasMatch(path)) {
      final id = path.split('/')[4];
      final current = _items[id];
      if (current == null) return _error(404, 'not_found');
      return _json({
        'revisions': current.$1.purged
            ? <Object?>[]
            : [
                current.$1.toJson(),
                for (final i in revisionsOf[id] ?? <Item>[]) i.toJson(),
              ],
      });
    }
    if (r.method == 'GET' &&
        RegExp(r'^/api/v1/orgs/[^/]+/settings/retention$').hasMatch(path)) {
      return _json(
        retention[path.split('/')[4]] ??
            {
              'server': {'auditDays': 365, 'maxVersions': 50, 'trashDays': 30},
              'org': {
                'auditDays': null,
                'maxVersions': null,
                'trashDays': null,
              },
            },
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
