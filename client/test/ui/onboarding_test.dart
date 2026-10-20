// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/session/session_store.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/ui/onboarding/join_screen.dart';
import 'package:unfeudal_client/src/ui/onboarding/recovery_kit_view.dart';
import 'package:unfeudal_client/src/ui/onboarding/setup_screen.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

/// Step 1: server and token, then on to the account step.
Future<void> fillServer(WidgetTester t) async {
  await t.enterText(
    find.byKey(const Key('setup-server')),
    'https://vault.test',
  );
  await t.enterText(
    find.byKey(const Key('setup-token')),
    'ABCD EFGH IJKL MNOP QRST UVWX YZ',
  );
  await t.tap(find.byKey(const Key('setup-next')));
  await t.pump();
}

Future<void> fillAccount(
  WidgetTester t, {
  String confirm = testPassword,
}) async {
  await t.enterText(find.byKey(const Key('setup-email')), testEmail);
  await t.enterText(find.byKey(const Key('setup-password')), testPassword);
  await t.enterText(find.byKey(const Key('setup-confirm')), confirm);
}

void main() {
  testWidgets('setup step 1 needs a token before the account step', (t) async {
    await pumpApp(
      t,
      state: testAppState(harness: SyncHarness())..stage = AppStage.setup,
    );
    final l = AppLocalizations.of(t.element(find.byType(SetupScreen)));
    await t.enterText(
      find.byKey(const Key('setup-server')),
      'https://vault.test',
    );
    await t.tap(find.byKey(const Key('setup-next')));
    await t.pump();
    expect(find.text(l.fieldRequired), findsOneWidget);
    expect(find.byKey(const Key('setup-email')), findsNothing);
  });

  testWidgets(
    'setup warns, checks the confirmation, then shows the kit before home',
    (t) async {
      final h = SyncHarness();
      final s = await pumpApp(
        t,
        state: testAppState(harness: h)..stage = AppStage.setup,
      );
      final l = AppLocalizations.of(t.element(find.byType(SetupScreen)));
      await fillServer(t);
      expect(find.text(l.setupWarning), findsOneWidget);
      await fillAccount(t, confirm: 'other-password');
      await t.tap(find.byKey(const Key('setup-submit')));
      await t.pump();
      expect(find.text(l.passwordsDiffer), findsOneWidget);
      await fillAccount(t);
      await t.tap(find.byKey(const Key('setup-submit')));
      await pumpReal(t);
      expect(find.byType(RecoveryKitView), findsOneWidget);
      expect(s.stage, AppStage.setup);
    },
  );

  testWidgets('no recovery_kit on the server: straight home, no kit', (
    t,
  ) async {
    final h = SyncHarness(capabilities: ['sync']);
    final s = await pumpApp(
      t,
      state: testAppState(harness: h)..stage = AppStage.setup,
    );
    await fillServer(t);
    await fillAccount(t);
    await t.tap(find.byKey(const Key('setup-submit')));
    await pumpReal(t);
    await t.pumpAndSettle();
    expect(s.stage, AppStage.home);
    expect(find.byType(RecoveryKitView).evaluate(), isEmpty);
  });

  testWidgets('join: a setup link prefills the setup screen', (t) async {
    final s = await pumpApp(t, state: testAppState()..stage = AppStage.join);
    final link = Enrollment(
      Uri.parse('https://vault.test'),
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
      EnrollKind.setup,
    ).toLink();
    await t.enterText(find.byKey(const Key('join-link')), link);
    await t.tap(find.byKey(const Key('join-submit')));
    await pumpReal(t, rounds: 5);
    expect(s.stage, AppStage.setup);
    expect(s.enrollment!.token, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ');
  });

  testWidgets('join: an invite creates the account', (t) async {
    final h = SyncHarness();
    final token = b64(List.filled(32, 4));
    h.invites[token] = 'dom@example.org';
    final s = await pumpApp(
      t,
      state: testAppState(harness: h)..stage = AppStage.join,
    );
    await t.enterText(
      find.byKey(const Key('join-link')),
      Enrollment(h.baseUrl, token, EnrollKind.invite).toLink(),
    );
    await t.tap(find.byKey(const Key('join-submit')));
    await pumpReal(t, rounds: 5);
    await t.enterText(find.byKey(const Key('join-email')), 'dom@example.org');
    await t.enterText(find.byKey(const Key('join-password')), 'password-456');
    await t.enterText(find.byKey(const Key('join-confirm')), 'password-456');
    await t.tap(find.byKey(const Key('join-accept')));
    await pumpReal(t);
    expect(find.byType(RecoveryKitView), findsOneWidget);
    expect(s.stored!.email, 'dom@example.org');
  });

  testWidgets('weak KDF in an enrollment file is refused', (t) async {
    // Sealed with 'file pass' under KdfParams.testing.
    final file = File('../shared/test/fixtures/v0/enrollment_encrypted.json')
        .readAsStringSync();
    final s = AppState(
      sessions: SessionStore(FakeSecureKv()),
      settingsStore: FakeSettingsStore(),
      openMirror: (_) async => LocalMirror.inMemory(),
    )..stage = AppStage.join;
    await pumpApp(
      t,
      state: s,
      child: JoinScreen(openFile: () async => file),
    );
    await t.tap(find.byKey(const Key('join-open-file')));
    await pumpReal(t, rounds: 3);
    await t.enterText(find.byKey(const Key('join-passphrase')), 'file pass');
    await t.tap(find.byKey(const Key('join-submit')));
    await pumpReal(t, rounds: 10);
    final l = AppLocalizations.of(t.element(find.byType(JoinScreen)));
    expect(find.text(l.errorWeakKdf), findsOneWidget);
    expect(s.enrollment, isNull);
  });
}
