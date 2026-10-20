// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/session/lock_machine.dart';

import 'support/fakes.dart';
import 'support/pump_app.dart';
import 'support/sync_harness.dart';

Future<(SyncHarness, AppState, FakeBiometricBackend)> home({
  List<String> capabilities = const [
    'biometric_unlock',
    'recovery_kit',
    'sync',
  ],
}) async {
  final h = SyncHarness(capabilities: capabilities);
  await h.createAccount('owner@example.org', 'password-000');
  await h.createAccount(testEmail, testPassword);
  final hw = FakeBiometricBackend();
  final s = testAppState(harness: h, biometrics: hw);
  await s.boot();
  await s.login(server: h.baseUrl, email: testEmail, password: testPassword);
  await s.sync!.syncNow();
  return (h, s, hw);
}

void main() {
  test(
    'enable, lock, unlock with biometrics: home again, offline too',
    () async {
      final (h, s, _) = await home();
      expect(await s.biometricAvailable(), isTrue);
      expect(await s.enableBiometrics(), isTrue);
      await s.lock();
      h.offline = true;
      expect(await s.unlockWithBiometrics(), isTrue);
      expect(
        (s.stage, s.vault!.isUnlocked, s.lockMachine.state),
        (AppStage.home, true, LockScreenState.success),
      );
    },
  );

  test('a cancelled prompt stays locked', () async {
    final (_, s, hw) = await home();
    await s.enableBiometrics();
    await s.lock();
    hw.cancel = true;
    expect(await s.unlockWithBiometrics(), isFalse);
    expect(
      (s.stage, s.lockMachine.state),
      (AppStage.unlock, LockScreenState.locked),
    );
  });

  test('device_revoked wipes the wrap; session_expired keeps it', () async {
    final (h, s, _) = await home();
    await s.enableBiometrics();
    h.expireSessions();
    await s.sync!.syncNow();
    expect(
      (s.signedOutBecause, await s.biometric!.isEnabled()),
      (SignOutReason.sessionExpired, true),
    );
    final (h2, s2, _) = await home();
    await s2.enableBiometrics();
    h2.devices[s2.stored!.deviceId]!.revokedAt = h2.now;
    await s2.sync!.syncNow();
    expect(
      (s2.signedOutBecause, await s2.biometric!.isEnabled()),
      (SignOutReason.deviceRevoked, false),
    );
  });

  test(
    'the server turning biometric_unlock off wipes the wrap at the next sync',
    () async {
      final (h, s, _) = await home();
      await s.enableBiometrics();
      h.capabilities = ['recovery_kit', 'sync'];
      await s.sync!.syncNow();
      expect(
        (await s.biometric!.isEnabled(), await s.biometricAvailable()),
        (false, false),
      );
    },
  );

  test(
    'a password change keeps the wrap valid; signing out wipes it',
    () async {
      final (_, s, _) = await home();
      await s.enableBiometrics();
      await s.changeMasterPassword(testPassword, 'another-long-password');
      await s.lock();
      expect(await s.unlockWithBiometrics(), isTrue);
      await s.signOut();
      expect(await s.biometric!.isEnabled(), isFalse);
    },
  );
}
