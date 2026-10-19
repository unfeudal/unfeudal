// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/ui/onboarding/recovery_kit_view.dart';
import 'package:unfeudal_client/src/ui/onboarding/recovery_screen.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  test('parseRecoveryKitText reads back what recoveryKitText writes', () {
    final key = RecoveryKey.encode(RecoveryKey.generate());
    final text = recoveryKitText((
      server: Uri.parse('https://vault.example.org'),
      email: 'camille@example.org',
      created: DateTime.utc(2026, 10, 15),
      recoveryKey: key,
      instructions: 'Keep it safe.',
    ));
    final kit = parseRecoveryKitText(text);
    expect(
      (kit.server, kit.email, kit.recoveryKey),
      (Uri.parse('https://vault.example.org'), 'camille@example.org', key),
    );
    expect(parseRecoveryKitText('hello'), (
      server: null,
      email: null,
      recoveryKey: null,
    ));
  });

  testWidgets(
    'a new device: the kit file fills the form; recovery then signs in here',
    (t) async {
      final h = SyncHarness();
      late String key;
      late String oldDevice;
      await t.runAsync(() async {
        await h.createAccount('owner@example.org', 'password-000');
        key = (await h.createAccount(
          testEmail,
          testPassword,
        )).account!.recoveryKey;
        oldDevice = (await h.signIn(
          email: testEmail,
          password: testPassword,
        )).deviceId;
      });
      final kit = recoveryKitText((
        server: h.baseUrl,
        email: testEmail,
        created: DateTime.utc(2026, 10, 15),
        recoveryKey: key,
        instructions: '',
      ));
      final s = testAppState(harness: h);
      await t.runAsync(s.boot);
      await pumpApp(
        t,
        state: s,
        child: RecoveryScreen(readKitFile: () async => kit),
      );
      await t.tap(find.byKey(const Key('recover-open-kit')));
      await pumpReal(t, rounds: 5);
      expect(find.text(testEmail), findsOneWidget);
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
      await t.tap(find.byKey(const Key('recovery-confirm')));
      await t.pump();
      await t.tap(find.byKey(const Key('recovery-continue')));
      await pumpReal(t, rounds: 60);
      expect((s.stage, s.vault!.isUnlocked), (AppStage.home, true));
      expect(h.devices[oldDevice]!.revokedAt, isNotNull);
      expect(h.devices.values.where((d) => d.revokedAt == null), hasLength(1));
    },
  );
}
