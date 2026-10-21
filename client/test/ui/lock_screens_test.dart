// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/app.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/session/lock_machine.dart';
import 'package:unfeudal_client/src/session/session_store.dart';
import 'package:unfeudal_client/src/settings/settings.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/ui/lock/login_screen.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

AppLocalizations l10n(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(Scaffold).first));

void main() {
  testWidgets('no session shows the login screen; a good login reaches home', (
    t,
  ) async {
    final h = SyncHarness();
    await t.runAsync(() => h.createAccount(testEmail, testPassword));
    final s = await pumpApp(
      t,
      state: testAppState(harness: h)..stage = AppStage.login,
    );
    expect(find.byType(LoginScreen), findsOneWidget);
    await t.enterText(
      find.byKey(const Key('login-server')),
      'https://vault.test',
    );
    await t.enterText(find.byKey(const Key('login-email')), testEmail);
    await t.enterText(find.byKey(const Key('login-password')), testPassword);
    await t.tap(find.byKey(const Key('login-submit')));
    await pumpReal(t);
    await t.pumpAndSettle();
    expect(s.stage, AppStage.home);
  });

  testWidgets('wrong password: explained, field shakes, nothing stored', (
    t,
  ) async {
    final h = SyncHarness();
    await t.runAsync(() => h.createAccount(testEmail, testPassword));
    final s = await pumpApp(
      t,
      state: testAppState(harness: h)..stage = AppStage.login,
    );
    await t.enterText(
      find.byKey(const Key('login-server')),
      'https://vault.test',
    );
    await t.enterText(find.byKey(const Key('login-email')), testEmail);
    await t.enterText(
      find.byKey(const Key('login-password')),
      'not-the-password',
    );
    await t.tap(find.byKey(const Key('login-submit')));
    await pumpReal(t);
    expect(find.text(l10n(t).errorUnauthorized), findsOneWidget);
    expect((s.stage, s.stored), (AppStage.login, null));
  });

  testWidgets('revoked device is explained on the login screen', (t) async {
    final s = await pumpApp(
      t,
      state: testAppState()
        ..stage = AppStage.login
        ..signedOutBecause = SignOutReason.deviceRevoked,
    );
    expect(find.text(l10n(t).loginDeviceRevoked), findsOneWidget);
    expect(s.stage, AppStage.login);
  });

  testWidgets('unlock: one check at a time, the button waits for it', (
    t,
  ) async {
    final s = await signedInState(t);
    await t.runAsync(s.lock);
    final checks = <LockScreenState>[];
    s.lockMachine.addListener(() {
      if (s.lockMachine.state == LockScreenState.checking) {
        checks.add(s.lockMachine.state);
      }
    });
    await pumpApp(t, state: s);
    await t.enterText(find.byKey(const Key('unlock-password')), testPassword);
    await t.tap(find.byKey(const Key('unlock-submit')));
    await t.pump();
    expect(
      t.widget<FilledButton>(find.byKey(const Key('unlock-submit'))).onPressed,
      isNull,
    );
    await t.tap(find.byKey(const Key('unlock-submit')));
    await pumpReal(t);
    await t.pumpAndSettle();
    expect(s.stage, AppStage.home);
    expect(checks, hasLength(1));
  });

  testWidgets(
    'unlock drives the lock machine: password, peek, error, success',
    (t) async {
      final s = await signedInState(t);
      await t.runAsync(s.lock);
      final states = <LockScreenState>[];
      s.lockMachine.addListener(() => states.add(s.lockMachine.state));
      await pumpApp(t, state: s);
      // The account chip on a known device.
      expect(find.text(testEmail), findsOneWidget);
      await t.tap(find.byKey(const Key('unlock-password')));
      await t.pump();
      await t.tap(find.byKey(const Key('unlock-peek')));
      await t.pump();
      await t.enterText(find.byKey(const Key('unlock-password')), 'wrong');
      await t.tap(find.byKey(const Key('unlock-submit')));
      await pumpReal(t);
      expect(s.lockMachine.state, LockScreenState.error);
      await t.enterText(find.byKey(const Key('unlock-password')), testPassword);
      await t.tap(find.byKey(const Key('unlock-submit')));
      await pumpReal(t);
      await t.pumpAndSettle();
      expect(s.stage, AppStage.home);
      expect(
        states,
        containsAllInOrder([
          LockScreenState.password,
          LockScreenState.peek,
          LockScreenState.checking,
          LockScreenState.error,
          LockScreenState.checking,
          LockScreenState.success,
        ]),
      );
    },
  );

  testWidgets(
    'theme and language come from the cached settings before unlock',
    (t) async {
      // pumpApp pins English, which would hide the cached language.
      final s = testAppState(
        settings: const Settings(themeMode: ThemeMode.dark, locale: 'fr'),
      );
      await t.runAsync(s.boot);
      await t.pumpWidget(UnfeudalApp(state: s));
      final app = t.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
      expect(app.locale, const Locale('fr'));
    },
  );

  testWidgets('a newer mirror shows a blocking screen with no action', (
    t,
  ) async {
    await pumpApp(
      t,
      state: AppState(
        sessions: SessionStore(FakeSecureKv()),
        settingsStore: FakeSettingsStore(),
        openMirror: (_) async => throw const MirrorTooNew(2),
      )..stage = AppStage.mirrorTooNew,
    );
    expect(find.text(l10n(t).mirrorTooNewTitle), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
}
