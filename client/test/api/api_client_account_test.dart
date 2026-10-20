// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/api/api_client.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/sync_harness.dart';

Future<(SyncHarness, ApiClient, HarnessLogin)> signedIn() async {
  final h = SyncHarness();
  // The first account is the Instance Owner.
  await h.createAccount('owner@example.org', 'password-000');
  final login = await h.signIn();
  final api = ApiClient(h.baseUrl, h.client)
    ..accessToken = login.accessToken
    ..refreshToken = login.refreshToken;
  return (h, api, login);
}

void main() {
  test('changePassword sends the expected body; the server signs out the other devices', () async {
    final (h, api, login) = await signedIn();
    final other = await h.signIn();
    final a = login.account;
    final changed = await AccountCrypto(
      kdf: KdfParams.testing,
      kdfFloor: KdfParams.testing,
    ).changePassword(a.account!.unlocked, a.bundle, 'new-password-1');
    await api.changePassword(
      currentAuthKey: unb64(a.authKey),
      bundle: changed.bundle,
      bundleVersion: 0,
      authKey: changed.authKey,
    );
    expect((a.bundleVersion, a.authKey), (1, b64(changed.authKey)));
    expect(h.devices[other.deviceId]!.revokedAt, isNotNull);
    expect(h.devices[login.deviceId]!.revokedAt, isNull);
    await expectLater(
      api.changePassword(
        currentAuthKey: List.filled(32, 0),
        bundle: changed.bundle,
        bundleVersion: 1,
        authKey: changed.authKey,
      ),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
    );
  });

  test('deleteAccount: 409 last_owner carries the sorted org names; success removes the account', () async {
    final (h, api, login) = await signedIn();
    login.account.lastOwnerOf = ['Beta', 'Acme'];
    final e = await api
        .deleteAccount(currentAuthKey: unb64(login.account.authKey))
        .then<Object>((_) => 'ok', onError: (Object e) => e);
    expect(
      e,
      isA<ApiException>()
          .having((x) => x.reason, 'reason', 'last_owner')
          .having((x) => x.orgs, 'orgs', ['Acme', 'Beta']),
    );
    login.account.lastOwnerOf = [];
    await api.deleteAccount(currentAuthKey: unb64(login.account.authKey));
    expect(h.accounts.keys, ['owner@example.org']);
  });

  test(
    'setLocale; read-only blocks deletion and locale, not the password change',
    () async {
      final (h, api, login) = await signedIn();
      await api.setLocale('fr');
      expect(login.account.locale, 'fr');
      await expectLater(api.setLocale('de'), throwsA(isA<ApiException>()));
      api.isReadOnly = () => true;
      await expectLater(api.setLocale('en'), throwsA(isA<ReadOnlyException>()));
      await expectLater(
        api.deleteAccount(currentAuthKey: List.filled(32, 0)),
        throwsA(isA<ReadOnlyException>()),
      );
      await expectLater(
        api.changePassword(
          currentAuthKey: List.filled(32, 0),
          bundle: login.account.bundle,
          bundleVersion: 0,
          authKey: List.filled(32, 1),
        ),
        throwsA(isA<ApiException>()),
        reason: 'sent, refused by the server, not by the read-only gate',
      );
    },
  );
}
