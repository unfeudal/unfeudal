// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:unfeudal_server/src/api/app.dart';
import 'package:unfeudal_server/src/api/errors.dart';
import 'package:unfeudal_server/src/api/json.dart';
import 'package:unfeudal_server/src/api/middleware.dart';
import 'package:unfeudal_server/src/net/client_ip.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/peer.dart';
import '../support/test_server.dart';

const u = '5d1e9a7c-2b3f-4c8d-9e0a-1b2c3d4e5f60';
const d = '8c7b6a59-4e3d-4c2b-a190-8f7e6d5c4b3a';

void main() {
  late TestServer s;
  setUp(() async => s = await TestServer.start());
  tearDown(() => s.close());

  Future<void> seed({bool owner = false}) async {
    final t = iso(s.clock.now());
    await s.db.execute(
      'INSERT INTO users (id, email, is_instance_owner, bundle, auth_hash, created_at) '
      "VALUES (@u, 'a@b.c', @o, '{}', 'h', @t)",
      {'u': u, 'o': owner, 't': t},
    );
    await s.db.execute(
      "INSERT INTO devices (id, user_id, name, platform, created_at, last_seen_at) VALUES (@d, @u, 'n', 'linux', @t, @t)",
      {'d': d, 'u': u, 't': t},
    );
  }

  Future<Response> call(
    Handler inner, {
    String method = 'GET',
    String path = '/api/v1/x',
    Map<String, String> headers = const {},
  }) async =>
      const Pipeline()
          .addMiddleware(withDeps(s.deps))
          .addMiddleware(errorMapper())
          .addHandler(inner)(
        Request(
          method,
          Uri.parse('https://vault.test$path'),
          headers: headers,
          context: {connectionInfoKey: FakePeer('203.0.113.7')},
        ),
      );

  test(
    'security headers on every response, errors and unknown routes included',
    () async {
      for (final r in [
        await s.get('/healthz'),
        await s.get('/nope'),
        await s.get('/api/v1/nope'),
        await s.get('/api/v1/x', headers: {'x-unfeudal-client': ''}),
      ]) {
        expect(r.headers, containsPair('x-content-type-options', 'nosniff'));
        expect(r.headers, containsPair('x-frame-options', 'DENY'));
        expect(r.headers, containsPair('referrer-policy', 'no-referrer'));
        expect(
          r.headers,
          containsPair(
            'content-security-policy',
            "default-src 'none'; frame-ancestors 'none'",
          ),
        );
        expect(r.headers, containsPair('cache-control', 'no-store'));
        expect(r.headers.keys, isNot(contains('access-control-allow-origin')));
      }
      final nf = await s.get('/api/v1/nope');
      expect(
        (nf.status, nf.error, nf.headers['content-type']),
        (404, 'not_found', 'application/json; charset=utf-8'),
      );
    },
  );

  test(
    'an unexpected exception is 500 internal; only path and type are logged',
    () async {
      final r = await call((_) => throw StateError('secret detail'));
      expect(r.statusCode, 500);
      expect(jsonDecode(await r.readAsString()), {
        'error': 'internal',
        'message': 'Internal error.',
      });
      final line = jsonDecode(s.logLines.last) as Map<String, Object?>;
      expect(line, {
        'level': 'error',
        'msg': 'internal',
        'path': 'api/v1/x',
        'type': 'StateError',
      });
      final api = await call(
        (_) => throw ApiError(
          ApiErrorCode.rateLimited,
          'Slow down.',
          retryAfter: 7,
          extra: {'x': 1},
        ),
      );
      expect((api.statusCode, api.headers['retry-after']), (429, '7'));
      expect(jsonDecode(await api.readAsString()), {
        'error': 'rate_limited',
        'message': 'Slow down.',
        'x': 1,
      });
    },
  );

  test('the request log has exactly method, path, status, ms, ip', () async {
    s.logLines.clear();
    await s.post(
      '/api/v1/nope?token=abc',
      body: {'password': 'p'},
      headers: {'authorization': 'Bearer zzz'},
    );
    final line = jsonDecode(s.logLines.single) as Map<String, Object?>;
    expect(line.keys, ['method', 'path', 'status', 'ms', 'ip']);
    expect(
      (line['method'], line['path'], line['status'], line['ip']),
      ('POST', '/api/v1/nope', 404, '203.0.113.7'),
    );
    expect(s.logLines.single, isNot(contains('zzz')));
  });

  test(
    'no trusted proxy and a private or loopback peer: one warning per process',
    () async {
      Future<void> from(String ip) async =>
          const Pipeline()
              .addMiddleware(withDeps(s.deps))
              .addMiddleware(requestLog())
              .addHandler((_) => Response.ok(''))(
            Request(
              'GET',
              Uri.parse('https://vault.test/healthz'),
              context: {connectionInfoKey: FakePeer(ip)},
            ),
          );
      s.logLines.clear();
      await from('203.0.113.7');
      expect(s.logLines.where((l) => l.contains('trusted_proxies')), isEmpty);
      await from('172.30.0.1');
      await from('127.0.0.1');
      expect(
        s.logLines.where((l) => l.contains('trusted_proxies')),
        hasLength(1),
      );
    },
  );

  test('X-Unfeudal-Client is required on /api/v1 only', () async {
    for (final v in ['', '1.2', '1.2.3-beta', 'v1.2.3']) {
      final r = await s.get('/api/v1/nope', headers: {'x-unfeudal-client': v});
      expect((r.status, r.error), (400, 'invalid_request'), reason: v);
    }
    expect(
      (await s.get('/healthz', headers: {'x-unfeudal-client': ''})).status,
      200,
    );
    expect(
      (await s.get('/api/info', headers: {'x-unfeudal-client': ''})).status,
      200,
    );
  });

  test('below min_client_version writes are 409 client_too_old except the account-protecting routes', () async {
    final gate = const Pipeline()
        .addMiddleware(clientVersionGate())
        .addHandler((_) => Response.ok('passed'));
    Future<(int, Object?)> run(String method, String path) async {
      final r = await call(
        gate,
        method: method,
        path: path,
        headers: {'x-unfeudal-client': '0.0.9'},
      );
      final text = await r.readAsString();
      return (
        r.statusCode,
        r.statusCode == 200 ? text : (jsonDecode(text) as Map)['reason'],
      );
    }

    expect(await run('GET', '/api/v1/sync'), (200, 'passed'));
    expect(await run('PUT', '/api/v1/items/x'), (409, 'client_too_old'));
    expect(await run('POST', '/api/v1/setup'), (409, 'client_too_old'));
    expect(await run('POST', '/api/v1/account/recovery-kit'), (
      409,
      'client_too_old',
    ));
    for (final (m, p) in [
      ('POST', '/api/v1/prelogin'),
      ('POST', '/api/v1/login'),
      ('POST', '/api/v1/token/refresh'),
      ('DELETE', '/api/v1/devices/$d'),
      ('POST', '/api/v1/account/password'),
      ('POST', '/api/v1/events/ssh'),
      ('POST', '/api/v1/events/reveal'),
    ]) {
      expect(await run(m, p), (200, 'passed'), reason: '$m $p');
    }
  });

  test(
    'requireAuth: bearer, MAC, expiry, then the user and device rows',
    () async {
      await seed(owner: true);
      final inner = requireAuth(
        (r) => jsonResponse({
          'u': authOf(r).userId,
          'd': authOf(r).deviceId,
          'io': authOf(r).isInstanceOwner,
        }),
      );
      Future<(int, Object?)> run(String? authorization) async {
        final r = await call(inner, headers: {'authorization': ?authorization});
        final body = jsonDecode(await r.readAsString()) as Map;
        return (
          r.statusCode,
          r.statusCode == 200
              ? '${body['u']} ${body['d']} ${body['io']}'
              : body['reason'],
        );
      }

      final token = s.deps.access.issue(u, d);
      expect(await run('Bearer $token'), (200, '$u $d true'));
      for (final bad in [
        null,
        token,
        'Basic $token',
        'Bearer ',
        'Bearer x.y',
      ]) {
        expect(await run(bad), (401, 'invalid_token'), reason: bad);
      }
      s.clock.advance(const Duration(minutes: 15));
      expect(await run('Bearer $token'), (401, 'invalid_token'));
    },
  );

  test(
    'requireAuth refuses a revoked device and a disabled user at once',
    () async {
      await seed();
      final token = s.deps.access.issue(u, d);
      final inner = requireAuth((_) => Response.ok(''));
      Future<Object?> reason() async {
        final r = await call(
          inner,
          headers: {'authorization': 'Bearer $token'},
        );
        return r.statusCode == 200
            ? 200
            : (jsonDecode(await r.readAsString()) as Map)['reason'];
      }

      expect(await reason(), 200);
      await s.db.execute('UPDATE users SET disabled = 1');
      expect(await reason(), 'device_revoked');
      await s.db.execute('UPDATE users SET disabled = 0');
      await s.db.execute(
        "UPDATE devices SET revoked_at = '2026-10-13T12:00:00.000Z'",
      );
      expect(await reason(), 'device_revoked');
      expect(
        await call(
          requireAuth((_) => Response.ok('')),
          headers: {
            'authorization': 'Bearer ${s.deps.access.issue(u, newId())}',
          },
        ).then((r) => r.statusCode),
        401,
      );
    },
  );

  test('requireFeature answers 404 feature_disabled', () async {
    final off = await TestServer.start(
      env: {'UNFEUDAL_FEATURE_RECOVERY_KIT': 'false'},
    );
    addTearDown(off.close);
    final r = await const Pipeline()
        .addMiddleware(withDeps(off.deps))
        .addMiddleware(errorMapper())
        .addMiddleware(requireFeature(Flag.recoveryKit))
        .addHandler(
          (_) => Response.ok(''),
        )(Request('GET', Uri.parse('https://vault.test/x')));
    expect(
      (r.statusCode, (jsonDecode(await r.readAsString()) as Map)['error']),
      (404, 'feature_disabled'),
    );
  });
}
