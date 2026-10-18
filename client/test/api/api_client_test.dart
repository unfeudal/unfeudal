// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:unfeudal_client/src/api/api_client.dart';
import 'package:unfeudal_client/src/version.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/sync_harness.dart';

Future<(SyncHarness, ApiClient, List<TokenPair>)> signedIn() async {
  final h = SyncHarness();
  final login = await h.signIn();
  final saved = <TokenPair>[];
  final api = ApiClient(h.baseUrl, h.client)
    ..accessToken = login.accessToken
    ..refreshToken = login.refreshToken
    ..onTokens = (t) async => saved.add(t);
  return (h, api, saved);
}

void main() {
  test('login: prelogin, then a Session; every /api/v1 call names the client version', () async {
    final seen = <String, String?>{};
    final h = SyncHarness();
    final acc = await h.createAccount('camille@example.org', 'password-123');
    final spy = MockClient((r) async {
      seen[r.url.path] = r.headers['x-unfeudal-client'];
      final copy = http.Request(r.method, r.url)
        ..headers.addAll(r.headers)
        ..bodyBytes = r.bodyBytes; // a MockClient request is already finalized
      return h.client.send(copy).then(http.Response.fromStream);
    });
    final api = ApiClient(h.baseUrl, spy);
    final pre = await api.prelogin('camille@example.org');
    expect(pre.salt, acc.bundle.salt);
    final session = await api.login(
      email: 'camille@example.org',
      authKey: acc.account!.authKey,
      device: (name: 'Windows', platform: 'windows'),
    );
    expect((session.userId, session.bundleVersion), (acc.userId, 0));
    expect(api.accessToken, session.accessToken);
    expect(seen['/api/v1/login'], clientVersion);
    expect(seen['/api/v1/prelogin'], clientVersion);
  });

  test('a 429 with retry-after ≤ 2 s is retried silently, at most 5 times; a longer one is not', () async {
    final waits = <Duration>[];
    var calls = 0;
    ApiClient with429(String after, {int times = 99}) =>
        ApiClient(
            Uri.parse('https://x.test'),
            MockClient((_) async {
              calls++;
              return calls <= times
                  ? http.Response(
                      '{"error":"rate_limited","message":""}',
                      429,
                      headers: {
                        'content-type': 'application/json',
                        'retry-after': after,
                      },
                    )
                  : http.Response('', 204);
            }),
          )
          ..accessToken = 'a.b'
          ..sleep = (d) async => waits.add(d);
    await with429('1', times: 3).revokeDevice('d');
    expect(calls, 4);
    expect(waits, List.filled(3, const Duration(seconds: 1)));
    calls = 0;
    waits.clear();
    await expectLater(
      with429('2').revokeDevice('d'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 429)),
    );
    expect((calls, waits.length), (6, 5));
    calls = 0;
    waits.clear();
    await expectLater(
      with429('3').revokeDevice('d'),
      throwsA(isA<ApiException>()),
    );
    expect((calls, waits.length), (1, 0));
  });

  test(
    'errors become ApiException with code, reason, item and retry-after',
    () async {
      http.Response reply(
        int status,
        String body, [
        Map<String, String> headers = const {},
      ]) => http.Response(
        body,
        status,
        headers: {'content-type': 'application/json', ...headers},
      );
      Future<Object> caught(http.Response res) =>
          (ApiClient(Uri.parse('https://x.test'), MockClient((_) async => res))
                ..accessToken = 'a.b')
              .devices()
              .then<Object>((_) => 'no error', onError: (Object e) => e);

      final limited = await caught(
        reply(429, '{"error":"rate_limited","message":"Slow down."}', {
          'retry-after': '7',
        }),
      ) as ApiException;
      expect(
        (limited.code, limited.status, limited.retryAfter, limited.message),
        ('rate_limited', 429, const Duration(seconds: 7), 'Slow down.'),
      );
      final unknown =
          await caught(reply(418, '{"error":"teapot"}')) as ApiException;
      expect(
        (unknown.code, unknown.known, unknown.message),
        ('teapot', null, ''),
      );
      final conflict = await caught(
        reply(
          409,
          '{"error":"conflict","message":"","item":null,"reason":"client_too_old"}',
        ),
      ) as ApiException;
      expect(
        (conflict.known, conflict.reason, conflict.item),
        (ApiErrorCode.conflict, 'client_too_old', null),
      );
      expect(await caught(reply(500, '<html>')), isA<FormatException>());
      final offline = ApiClient(
        Uri.parse('https://x.test'),
        MockClient((r) async => throw http.ClientException('down')),
      );
      await expectLater(
        offline.prelogin('a@b.c'),
        throwsA(isA<NetworkException>()),
      );
    },
  );

  test(
    'concurrent 401s refresh once and persist the new token first',
    () async {
      final (h, api, saved) = await signedIn();
      h.expireAccess();
      api.onTokens = (t) async {
        expect(api.refreshToken, isNot(t.refreshToken)); // persisted before use
        saved.add(t);
      };
      final results = await Future.wait([
        api.devices(),
        api.devices(),
        api.sync(cursor: 0),
      ]);
      expect(results, hasLength(3));
      expect(
        h.requests.where((r) => r == 'POST /api/v1/token/refresh'),
        hasLength(1),
      );
      expect(saved.single.refreshToken, api.refreshToken);
    },
  );

  test(
    'a failed refresh surfaces its reason; a spent token is not reused',
    () async {
      final (h, api, _) = await signedIn();
      final stale = api.refreshToken!;
      await api.refresh();
      api
        ..refreshToken =
            stale // replay
        ..accessToken = 'gone.x';
      await expectLater(
        api.devices(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.reason,
            'reason',
            'device_revoked',
          ),
        ),
      );
      expect(h.devices.values.first.revokedAt, isNotNull);
      final (h2, api2, _) = await signedIn();
      h2.expireSessions();
      await expectLater(
        api2.devices(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.reason,
            'reason',
            'session_expired',
          ),
        ),
      );
    },
  );

  test('info: public without a token, full with one, refreshed when the token went stale', () async {
    final (h, api, _) = await signedIn();
    final public = await ApiClient(h.baseUrl, h.client).info();
    expect((public.server, public.instanceEpoch), (null, null));
    expect((await api.info()).instanceEpoch, h.instanceEpoch);
    h.expireAccess();
    expect((await api.info()).server, '0.1.0');
    expect(h.requests.where((r) => r.endsWith('/token/refresh')), hasLength(1));
  });

  test('putItem sends If-Match and returns the stored item; 409 carries the current item', () async {
    final (h, api, _) = await signedIn();
    final id = newId();
    final stored = await api.putItem(wireItem(id, revision: 0), ifMatch: 0);
    expect(stored.revision, 1);
    final e = await api
        .putItem(wireItem(id), ifMatch: 0)
        .then<Object>((_) => 'ok', onError: (Object e) => e);
    expect(e, isA<ApiException>().having((x) => x.item?.revision, 'item', 1));
  });

  test('read-only blocks writes except device revocation', () async {
    final (h, api, _) = await signedIn();
    api.readOnly = true;
    await expectLater(
      api.putItem(wireItem(newId(), revision: 0), ifMatch: 0),
      throwsA(isA<ReadOnlyException>()),
    );
    await expectLater(
      api.changeRecoveryKit(
        currentAuthKey: List.filled(32, 0),
        bundle: h.accounts.values.first.bundle,
        bundleVersion: 0,
        recoveryAuthKey: List.filled(32, 0),
      ),
      throwsA(isA<ReadOnlyException>()),
    );
    expect(await api.sync(cursor: 0), isA<SyncPage>());
    final other = await h.signIn();
    await api.revokeDevice(other.deviceId);
    expect(h.devices[other.deviceId]!.revokedAt, isNotNull);
  });

  test('invite accept creates a session; an existing account is a 409 account_exists', () async {
    final h = SyncHarness();
    final token = b64(List.filled(32, 3));
    h.invites[token] = 'dom@example.org';
    final acc = await AccountCrypto(
      kdf: KdfParams.testing,
      allowTestingKdf: true,
    ).create('password-456');
    final api = ApiClient(h.baseUrl, h.client);
    final s = await api.acceptInvite(
      token: token,
      email: 'dom@example.org',
      bundle: acc.bundle,
      authKey: acc.authKey,
      recoveryAuthKey: acc.recoveryAuthKey,
      device: (name: 'macOS', platform: 'macos'),
      locale: 'fr',
    );
    expect(s.isInstanceOwner, isFalse);
    h.invites[token] = 'dom@example.org';
    await expectLater(
      api.acceptInvite(
        token: token,
        email: 'dom@example.org',
        bundle: acc.bundle,
        authKey: acc.authKey,
        recoveryAuthKey: acc.recoveryAuthKey,
        device: (name: 'macOS', platform: 'macos'),
      ),
      throwsA(
        isA<ApiException>().having((e) => e.reason, 'reason', 'account_exists'),
      ),
    );
  });
}
