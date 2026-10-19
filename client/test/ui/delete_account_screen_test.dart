// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/ui/settings/delete_account_screen.dart';
import 'package:unfeudal_client/src/ui/settings/settings_screen.dart';

import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  testWidgets(
    'the typed email unlocks the button; last owner shows the org names',
    (t) async {
      final h = SyncHarness();
      await t.runAsync(
        () => h.createAccount('owner@example.org', 'password-000'),
      );
      final s = await signedInState(t, harness: h);
      h.accounts[testEmail]!.lastOwnerOf = ['Beta', 'Acme'];
      await pumpApp(t, state: s, child: const DeleteAccountScreen());
      await t.enterText(find.byKey(const Key('delete-password')), testPassword);
      await t.tap(find.byKey(const Key('delete-submit')));
      await pumpReal(t, rounds: 5);
      expect(
        h.requests.where((r) => r == 'DELETE /api/v1/account'),
        isEmpty,
        reason: 'email not typed yet',
      );
      await t.enterText(
        find.byKey(const Key('delete-confirm-email')),
        testEmail,
      );
      await t.tap(find.byKey(const Key('delete-submit')));
      await pumpReal(t, rounds: 40);
      expect(find.textContaining('Acme, Beta'), findsOneWidget);
      h.accounts[testEmail]!.lastOwnerOf = [];
      await t.tap(find.byKey(const Key('delete-submit')));
      await pumpReal(t, rounds: 40);
      expect(s.stage, AppStage.login);
    },
  );

  testWidgets('the Instance Owner has no deletion entry', (t) async {
    final s = await signedInState(
      t,
    ); // first account of the harness: Instance Owner
    await pumpApp(
      t,
      state: s,
      child: const SettingsScreen(initialGroup: 'account'),
    );
    await pumpReal(t, rounds: 5);
    expect(find.byKey(const Key('settings-delete-account')), findsNothing);
  });
}
