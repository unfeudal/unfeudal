// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/ui/onboarding/recovery_kit_view.dart';
import 'package:unfeudal_client/src/ui/settings/password_change_screen.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/pump_app.dart';
import '../support/sync_harness.dart';

Future<void> fill(
  WidgetTester t, {
  String current = testPassword,
  String next = 'another-long-password',
  String? confirm,
}) async {
  await t.enterText(find.byKey(const Key('pw-current')), current);
  await t.enterText(find.byKey(const Key('pw-next')), next);
  await t.enterText(find.byKey(const Key('pw-confirm')), confirm ?? next);
  await t.tap(find.byKey(const Key('pw-submit')));
  await pumpReal(t, rounds: 40);
}

AppLocalizations l10n(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(PasswordChangeScreen)));
bool isPost(String r) => r == 'POST /api/v1/account/password';

void main() {
  testWidgets('a weak, mismatched or wrong current password sends nothing', (
    t,
  ) async {
    final h = SyncHarness();
    final s = await signedInState(t, harness: h);
    await pumpApp(t, state: s, child: const PasswordChangeScreen());
    await fill(t, next: 'short');
    expect(
      find.text(l10n(t).errorWeakPassword(AccountCrypto.minPasswordLength)),
      findsOneWidget,
    );
    await fill(t, confirm: 'something-else');
    expect(find.text(l10n(t).passwordsDiffer), findsOneWidget);
    await fill(t, current: 'not-the-password');
    expect(find.text(l10n(t).passwordCurrentWrong), findsOneWidget);
    expect(h.requests.where(isPost), isEmpty);
  });

  testWidgets(
    'success: other devices signed out, vault open, the new password unlocks offline',
    (t) async {
      final h = SyncHarness();
      final s = await signedInState(t, harness: h);
      late String other;
      await t.runAsync(
        () async => other = (await h.signIn(
          email: testEmail,
          password: testPassword,
        )).deviceId,
      );
      await pumpApp(t, state: s, child: const PasswordChangeScreen());
      await fill(t);
      expect(h.requests.where(isPost), hasLength(1));
      expect(h.devices[other]!.revokedAt, isNotNull);
      expect(s.vault!.isUnlocked, true);
      await t.runAsync(() async {
        await s.lock();
        h.offline = true;
        await s.unlock('another-long-password');
      });
      expect(s.stage, AppStage.home);
    },
  );

  testWidgets('security reset: new password, then a new recovery kit', (
    t,
  ) async {
    final h = SyncHarness();
    final s = await signedInState(t, harness: h);
    final before = h.accounts[testEmail]!.recoveryAuthKey;
    await pumpApp(
      t,
      state: s,
      child: const PasswordChangeScreen(securityReset: true),
    );
    await fill(t);
    expect(find.byType(RecoveryKitView), findsOneWidget);
    expect(
      (
        h.accounts[testEmail]!.recoveryAuthKey == before,
        h.accounts[testEmail]!.bundleVersion,
      ),
      (false, 2),
    );
  });

  testWidgets(
    'security reset without recovery_kit: password changed, the kit step explained',
    (t) async {
      final h = SyncHarness(capabilities: const ['sync']);
      final s = await signedInState(t, harness: h);
      await pumpApp(
        t,
        state: s,
        child: const PasswordChangeScreen(securityReset: true),
      );
      await fill(t);
      expect(find.text(l10n(t).securityResetNoKit), findsOneWidget);
      expect(h.requests.where(isPost), hasLength(1));
      expect(
        h.requests.where((r) => r.endsWith('/account/recovery-kit')),
        isEmpty,
      );
    },
  );
}
