// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/design/seal.dart';
import 'package:unfeudal_client/src/ui/hosts/host_key_dialog.dart';
import 'package:unfeudal_client/src/ui/shell/home_shell.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';

void main() {
  testWidgets(
    'connect from the tree: unknown-key dialog, then a tab with a seal',
    (t) async {
      final ssh = FakeSshConnector()
        ..keyType = 'ssh-ed25519'
        ..fingerprint = 'SHA256:${'C' * 43}';
      final s = await signedInState(t, ssh: ssh);
      late String id;
      await t.runAsync(
        () async => id = await s.vault!.upsertItem(
          type: 'host',
          meta: hostJson('web', user: 'root'),
        ),
      );
      await pumpApp(t, state: s);
      await pumpReal(t, rounds: 5);
      final l = AppLocalizations.of(t.element(find.byType(HomeShell)));
      expect(find.text(l.tabsEmpty), findsOneWidget);
      await t.tap(find.byKey(Key('host-$id')));
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await pumpReal(t, rounds: 5);
      expect(find.byType(HostKeyUnknownDialog), findsOneWidget);
      await t.tap(find.byKey(const Key('hostkey-trust')));
      await pumpReal(t, rounds: 10);
      expect(s.tabs.single.state, SealState.connected);
      expect(find.byKey(const Key('tab-0')), findsOneWidget);
    },
  );

  testWidgets('a refused key leaves a tab with the reason, never toString()', (
    t,
  ) async {
    final ssh = FakeSshConnector()
      ..keyType = 'ssh-ed25519'
      ..fingerprint = 'SHA256:${'C' * 43}';
    final s = await signedInState(t, ssh: ssh);
    late String id;
    await t.runAsync(
      () async => id = await s.vault!.upsertItem(
        type: 'host',
        meta: hostJson('web', user: 'root'),
      ),
    );
    await pumpApp(t, state: s);
    await pumpReal(t, rounds: 5);
    await t.tap(find.byKey(Key('host-$id')));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpReal(t, rounds: 5);
    await t.tap(find.byKey(const Key('hostkey-cancel')));
    await pumpReal(t, rounds: 5);
    final l = AppLocalizations.of(t.element(find.byType(HomeShell)));
    expect(find.text(l.errorHostKeyUnknown), findsOneWidget);
    expect(find.textContaining('HostKeyRejected'), findsNothing);
    await t.tap(find.byKey(const Key('tab-close-0')));
    await t.pump();
    expect(s.tabs, isEmpty);
  });
}
