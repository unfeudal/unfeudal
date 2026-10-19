// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/ui/onboarding/recovery_kit_view.dart';
import 'package:unfeudal_client/src/ui/onboarding/recovery_screen.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  testWidgets('recovery resets the password and shows the new kit', (t) async {
    final h = SyncHarness();
    late String key;
    await t.runAsync(
      () async => key = (await h.createAccount(
        testEmail,
        testPassword,
      )).account!.recoveryKey,
    );
    final s = await pumpApp(
      t,
      state: testAppState(harness: h)..stage = AppStage.login,
      child: const RecoveryScreen(),
    );
    await t.enterText(
      find.byKey(const Key('recover-server')),
      'https://vault.test',
    );
    await t.enterText(find.byKey(const Key('recover-email')), testEmail);
    await t.enterText(
      find.byKey(const Key('recover-key')),
      key.toLowerCase().replaceAll('-', ' '),
    );
    await t.tap(find.byKey(const Key('recover-next')));
    await t.pump();
    await t.enterText(
      find.byKey(const Key('recover-password')),
      'new-password-1',
    );
    await t.enterText(
      find.byKey(const Key('recover-confirm')),
      'new-password-1',
    );
    await t.tap(find.byKey(const Key('recover-submit')));
    await pumpReal(t, rounds: 60);
    expect(find.byType(RecoveryKitView), findsOneWidget);
    expect(find.text(key), findsNothing); // a new key
    expect(h.accounts[testEmail]!.bundleVersion, 1);
    expect(s.stage, AppStage.login);
  });

  testWidgets('a mistyped key is refused before any request', (t) async {
    final h = SyncHarness();
    await pumpApp(
      t,
      state: testAppState(harness: h),
      child: const RecoveryScreen(),
    );
    await t.enterText(
      find.byKey(const Key('recover-server')),
      'https://vault.test',
    );
    await t.enterText(find.byKey(const Key('recover-email')), testEmail);
    await t.enterText(find.byKey(const Key('recover-key')), 'AAAA-BBBB');
    await t.tap(find.byKey(const Key('recover-next')));
    await pumpReal(t, rounds: 5);
    final l = AppLocalizations.of(t.element(find.byType(RecoveryScreen)));
    expect(find.text(l.errorInvalidRecoveryKey), findsOneWidget);
    expect(h.requests.where((r) => r.contains('/account/recover')), isEmpty);
    expect(find.byKey(const Key('recover-password')), findsNothing);
  });
}
