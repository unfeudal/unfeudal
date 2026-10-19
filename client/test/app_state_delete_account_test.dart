// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/api/api_client.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/session/session_store.dart';
import 'package:unfeudal_client/src/settings/settings.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'support/fakes.dart';
import 'support/pump_app.dart';
import 'support/sync_harness.dart';

Future<(SyncHarness, AppState, FakeSecureKv, Directory)> signedIn() async {
  final h = SyncHarness(
    capabilities: const ['biometric_unlock', 'recovery_kit', 'sync'],
  );
  await h.createAccount('owner@example.org', 'password-000');
  await h.createAccount(testEmail, testPassword);
  final dir = Directory.systemTemp.createTempSync('uf_delete_');
  final kv = FakeSecureKv();
  final s = AppState(
    sessions: SessionStore(kv),
    settingsStore: SettingsStore.memory(),
    openMirror: (id) async => LocalMirror.open('${dir.path}/mirror-$id.sqlite'),
    httpClient: h.client,
    biometrics: FakeBiometricBackend(),
    allowTestingKdf: true,
    kdf: KdfParams.testing,
  );
  await s.boot();
  await s.login(server: h.baseUrl, email: testEmail, password: testPassword);
  await s.sync!.syncNow();
  return (h, s, kv, dir);
}

void main() {
  test('the password is checked here, the server deletes, then this device forgets everything', () async {
    final (h, s, kv, dir) = await signedIn();
    addTearDown(() => dir.deleteSync(recursive: true));
    expect(await s.enableBiometrics(), isTrue);
    await expectLater(
      s.deleteAccount('wrong-password'),
      throwsA(isA<WrongPassword>()),
    );
    expect(h.requests.where((r) => r == 'DELETE /api/v1/account'), isEmpty);
    await s.deleteAccount(testPassword);
    expect(h.accounts.containsKey(testEmail), isFalse);
    expect(s.stage, AppStage.login);
    expect(kv.values, isEmpty);
    expect(dir.listSync(), isEmpty);
  });

  test('last owner: 409 with the org names; nothing wiped', () async {
    final (h, s, kv, dir) = await signedIn();
    addTearDown(() {
      s.mirror?.close(); // Windows keeps an open SQLite file
      dir.deleteSync(recursive: true);
    });
    h.accounts[testEmail]!.lastOwnerOf = ['Acme'];
    await expectLater(
      s.deleteAccount(testPassword),
      throwsA(
        isA<ApiException>()
            .having((e) => e.reason, 'reason', 'last_owner')
            .having((e) => e.orgs, 'orgs', ['Acme']),
      ),
    );
    expect(s.stage, AppStage.home);
    expect(kv.values, isNotEmpty);
    expect(dir.listSync(), isNotEmpty);
  });
}
