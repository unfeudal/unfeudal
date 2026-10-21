// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/design/seal.dart';
import 'package:unfeudal_client/src/loquet/loquet.dart';
import 'package:unfeudal_client/src/loquet/loquet_pose.dart';
import 'package:unfeudal_client/src/ssh/ssh_connector.dart';
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
      final s = await connectFromTree(t, ssh);
      expect(find.byType(HostKeyUnknownDialog), findsOneWidget);
      await t.tap(find.byKey(const Key('hostkey-trust')));
      await pumpReal(t, rounds: 10);
      expect(s.connections.tabs.single.state, SealState.connected);
      expect(find.byKey(const Key('tab-0')), findsOneWidget);
    },
  );

  testWidgets('a refused key leaves a tab with the reason, never toString()', (
    t,
  ) async {
    final ssh = FakeSshConnector()
      ..keyType = 'ssh-ed25519'
      ..fingerprint = 'SHA256:${'C' * 43}';
    final s = await connectFromTree(t, ssh);
    await t.tap(find.byKey(const Key('hostkey-cancel')));
    await pumpReal(t, rounds: 5);
    final l = AppLocalizations.of(t.element(find.byType(HomeShell)));
    expect(find.text(l.errorHostKeyUnknown), findsOneWidget);
    expect(find.textContaining('HostKeyRejected'), findsNothing);
    await t.tap(find.byKey(const Key('tab-close-0')));
    await t.pump();
    expect(s.connections.tabs, isEmpty);
  });

  testWidgets('refused credentials: the tab shows why, retry reconnects', (
    t,
  ) async {
    final ssh = FakeSshConnector()..failWith = const SshAuthFailed();
    final s = await connectFromTree(t, ssh);
    final l = AppLocalizations.of(t.element(find.byType(HomeShell)));
    expect(find.text(l.errorSshAuth), findsOneWidget);
    expect(find.text(l.tabErrorTitle('web')), findsOneWidget);
    expect(find.byKey(const Key('tab-edit-host')), findsOneWidget);
    final face = t.widget<Loquet>(
      find.descendant(
        of: find.byKey(const Key('tab-error-card')),
        matching: find.byType(Loquet),
      ),
    );
    expect(
      (face.mood, face.size),
      (LoquetMood.sad, 88.0),
      reason: 'an error state, 80-96 px',
    );
    await t.tap(find.byKey(const Key('tab-retry')));
    await pumpReal(t, rounds: 5);
    expect(ssh.targets, hasLength(2));
    expect(s.connections.tabs, hasLength(1));
  });

  testWidgets('retry keeps the failed tab in its place', (t) async {
    final ssh = FakeSshConnector()..failWith = const SshAuthFailed();
    final s = await signedInState(t, ssh: ssh);
    late String failed, other;
    await t.runAsync(() async {
      failed = await s.vault!.upsertItem(
        type: 'host',
        meta: hostJson('web', user: 'root'),
      );
      other = await s.vault!.upsertItem(
        type: 'host',
        meta: hostJson('db', user: 'root'),
      );
      await s.vault!.hostKeys.pin(other, 'ssh-ed25519', 'SHA256:${'A' * 43}');
    });
    await pumpApp(t, state: s);
    await pumpReal(t, rounds: 5);
    Future<void> open(String id) async {
      await t.tap(find.byKey(Key('host-$id')));
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await pumpReal(t, rounds: 5);
    }

    await open(failed);
    ssh.failWith = null;
    await open(other);
    await t.tap(find.byKey(const Key('tab-0')));
    await pumpReal(t, rounds: 5);

    await t.tap(find.byKey(const Key('tab-retry')));
    await pumpReal(t, rounds: 5);

    expect([for (final tab in s.connections.tabs) tab.hostId], [failed, other]);
  });

  testWidgets('a refused changed host key shows Loquet alert, not sad', (
    t,
  ) async {
    final ssh = FakeSshConnector()
      ..failWith = const HostKeyRejected(HostKeyDecision.changed);
    await connectFromTree(t, ssh);
    final face = t.widget<Loquet>(
      find.descendant(
        of: find.byKey(const Key('tab-error-card')),
        matching: find.byType(Loquet),
      ),
    );
    expect(face.mood, LoquetMood.alert);
  });
}

Future<AppState> connectFromTree(WidgetTester t, FakeSshConnector ssh) async {
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
  return s;
}
