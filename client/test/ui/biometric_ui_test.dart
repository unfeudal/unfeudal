// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/ui/lock/unlock_screen.dart';
import 'package:unfeudal_client/src/ui/settings/settings_screen.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

Future<AppState> signedIn(WidgetTester t, FakeBiometricBackend hw) async {
  final h = SyncHarness(capabilities: const ['biometric_unlock', 'sync']);
  late AppState s;
  await t.runAsync(() async {
    await h.createAccount('owner@example.org', 'password-000');
    await h.createAccount(testEmail, testPassword);
    s = testAppState(harness: h, biometrics: hw);
    await s.boot();
    await s.login(server: h.baseUrl, email: testEmail, password: testPassword);
    await s.sync!.syncNow();
  });
  return s;
}

void main() {
  testWidgets('settings toggle enables it; the lock screen button unlocks', (
    t,
  ) async {
    final s = await signedIn(t, FakeBiometricBackend());
    await pumpApp(
      t,
      state: s,
      child: const SettingsScreen(initialGroup: 'security'),
    );
    await pumpReal(t, rounds: 5);
    await t.tap(find.byKey(const Key('settings-biometric')));
    await pumpReal(t, rounds: 5);
    expect(await t.runAsync(() => s.biometric!.isEnabled()), isTrue);
    await t.runAsync(s.lock);
    await pumpApp(t, state: s, child: const UnlockScreen());
    await pumpReal(t, rounds: 5);
    await t.tap(find.byKey(const Key('unlock-biometric')));
    await pumpReal(t, rounds: 20);
    expect(s.stage, AppStage.home);
  });

  testWidgets('no hardware: no toggle and no button', (t) async {
    final s = await signedIn(t, FakeBiometricBackend(isAvailable: false));
    await pumpApp(
      t,
      state: s,
      child: const SettingsScreen(initialGroup: 'security'),
    );
    await pumpReal(t, rounds: 5);
    expect(find.byKey(const Key('settings-biometric')), findsNothing);
    await t.runAsync(s.lock);
    await pumpApp(t, state: s, child: const UnlockScreen());
    await pumpReal(t, rounds: 5);
    expect(find.byKey(const Key('unlock-biometric')), findsNothing);
  });
}
