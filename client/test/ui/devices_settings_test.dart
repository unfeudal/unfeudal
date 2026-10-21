// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/ui/devices/devices_screen.dart';
import 'package:unfeudal_client/src/ui/onboarding/recovery_kit_view.dart';
import 'package:unfeudal_client/src/ui/settings/settings_screen.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/pump_app.dart';
import '../support/sync_harness.dart';

// A signed-in device list with a second device of the same account, whose id is returned.
Future<(SyncHarness, AppState, String)> pumpDeviceList(WidgetTester t) async {
  final h = SyncHarness();
  final s = await signedInState(t, harness: h);
  late String other;
  await t.runAsync(() async => other = (await h.signIn()).deviceId);
  await pumpApp(
    t,
    state: s,
    child: const Scaffold(body: DeviceList()),
  );
  await pumpReal(t, rounds: 5);
  return (h, s, other);
}

void main() {
  testWidgets('devices: the current device is marked', (t) async {
    final (_, s, _) = await pumpDeviceList(t);
    expect(
      find.byKey(Key('device-current-${s.stored!.deviceId}')),
      findsOneWidget,
    );
  });

  testWidgets('devices: revoking another device revokes it', (t) async {
    final (h, _, other) = await pumpDeviceList(t);
    await t.tap(find.byKey(Key('revoke-$other')));
    await pumpReal(t, rounds: 5);
    expect(h.devices[other]!.revokedAt, isNotNull);
  });

  testWidgets('devices: revoking this device asks, then signs out', (t) async {
    final (_, s, _) = await pumpDeviceList(t);
    await t.tap(find.byKey(Key('revoke-${s.stored!.deviceId}')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirm-yes')));
    await pumpReal(t, rounds: 5);
    expect(s.stage, AppStage.login);
  });

  testWidgets('settings: the theme is synced to the profile', (t) async {
    final s = await signedInState(t);
    await pumpApp(t, state: s, child: const SettingsScreen());
    await t.tap(find.byKey(const Key('theme-dark')));
    await pumpReal(t, rounds: 5);
    expect(s.settings.themeMode, ThemeMode.dark);
    expect(s.vault!.profile.meta.prefs['themeMode'], 'dark');
  });

  testWidgets('settings: auto-lock stays on this device', (t) async {
    final s = await signedInState(t);
    await pumpApp(
      t,
      state: s,
      child: const SettingsScreen(initialGroup: 'security'),
    );
    await t.tap(find.byKey(const Key('autolock')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('autolock-5')).last);
    await pumpReal(t, rounds: 5);
    expect(s.settings.autoLockMinutes, 5);
    expect(s.vault!.profile.meta.prefs.containsKey('autoLockMinutes'), isFalse);
  });

  testWidgets('settings: the safety code is shown', (t) async {
    final s = await signedInState(t);
    await pumpApp(
      t,
      state: s,
      child: const SettingsScreen(initialGroup: 'security'),
    );
    expect(find.text(safetyCode(s.credentials.publicKey)), findsOneWidget);
  });

  testWidgets(
    'recovery kit regeneration asks the password, then shows the new kit',
    (t) async {
      final h = SyncHarness();
      final s = await signedInState(t, harness: h);
      await pumpApp(
        t,
        state: s,
        child: const SettingsScreen(initialGroup: 'security'),
      );
      await t.tap(find.byKey(const Key('settings-recovery-kit')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('confirm-password')),
        testPassword,
      );
      await t.tap(find.byKey(const Key('confirm-password-ok')));
      await pumpReal(t, rounds: 40);
      expect(find.byType(RecoveryKitView), findsOneWidget);
      expect(h.accounts[testEmail]!.bundleVersion, 1);
    },
  );

  testWidgets('no recovery_kit on the server: no regeneration entry', (
    t,
  ) async {
    final s = await signedInState(
      t,
      harness: SyncHarness(capabilities: ['sync']),
    );
    await pumpApp(
      t,
      state: s,
      child: const SettingsScreen(initialGroup: 'security'),
    );
    await pumpReal(t, rounds: 5);
    expect(find.byKey(const Key('settings-recovery-kit')), findsNothing);
  });
}
