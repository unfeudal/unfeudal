// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/design/rows.dart';
import 'package:unfeudal_client/src/keys/key_tools.dart';
import 'package:unfeudal_client/src/ui/import/import_preview_screen.dart';
import 'package:unfeudal_client/src/ui/settings/settings_screen.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  Future<AppState> pumpWithDuplicate(WidgetTester t) async {
    final s = await signedInState(
      t,
      harness: SyncHarness(capabilities: const ['ssh_config_import', 'sync']),
    );
    await t.runAsync(
      () => s.vault!.upsertItem(type: 'host', meta: hostJson('old')),
    );
    await pumpApp(
      t,
      state: s,
      child: ImportPreviewScreen(
        configPath: '/home/c/.ssh/config',
        home: '/home/c',
        readFile: (p) async =>
            p == '/home/c/.ssh/config' ? 'Host a\nHost old\n' : null,
      ),
    );
    await pumpReal(t, rounds: 10);
    return s;
  }

  testWidgets('duplicates start unchecked; the button counts the selection', (
    t,
  ) async {
    await pumpWithDuplicate(t);
    final l = AppLocalizations.of(t.element(find.byType(ImportPreviewScreen)));
    expect(find.text(l.importCount(1)), findsOneWidget);
    await t.tap(find.byKey(const Key('import-row-old')));
    await t.pump();
    expect(find.text(l.importCount(2)), findsOneWidget);
  });

  testWidgets('import writes the chosen hosts', (t) async {
    final s = await pumpWithDuplicate(t);
    await t.tap(find.byKey(const Key('import-submit')));
    await pumpReal(t, rounds: 20);
    expect(
      s.vault!.ofKind(ItemKind.host).map((e) => e.name),
      unorderedEquals(['old', 'a']),
    );
  });

  testWidgets('an unreadable config shows the error instead of the spinner', (
    t,
  ) async {
    final s = await signedInState(
      t,
      harness: SyncHarness(capabilities: const ['ssh_config_import', 'sync']),
    );
    await pumpApp(
      t,
      state: s,
      child: ImportPreviewScreen(
        configPath: '/home/c/.ssh/config',
        home: '/home/c',
        readFile: (p) async => throw FileSystemException('denied', p),
      ),
    );
    await pumpReal(t, rounds: 10);
    final l = AppLocalizations.of(t.element(find.byType(ImportPreviewScreen)));
    expect(find.text(l.errorUnexpected('FileSystemException')), findsOneWidget);
    expect(find.byType(UfLoading), findsNothing);
  });

  testWidgets('a key the passphrase does not open is reported after import', (
    t,
  ) async {
    final s = await signedInState(
      t,
      harness: SyncHarness(capabilities: const ['ssh_config_import', 'sync']),
    );
    late String pem;
    await t.runAsync(
      () async => pem = (await generateEd25519(passphrase: 'pp')).privateKeyPem,
    );
    await pumpApp(
      t,
      state: s,
      child: ImportPreviewScreen(
        configPath: '/home/c/.ssh/config',
        home: '/home/c',
        readFile: (p) async => switch (p) {
          '/home/c/.ssh/config' => 'Host a\n  IdentityFile ~/.ssh/k\n',
          '/home/c/.ssh/k' => pem,
          _ => null,
        },
      ),
    );
    await pumpReal(t, rounds: 10);
    final l = AppLocalizations.of(t.element(find.byType(ImportPreviewScreen)));
    await t.enterText(find.byKey(const Key('import-passphrase-0')), 'nope');
    await t.tap(find.byKey(const Key('import-submit')));
    await pumpReal(t, rounds: 20);
    expect(
      find.text(
        [
          l.importDone(1),
          l.importWarning(1, l.importProblemKeyUnreadable),
        ].join('\n'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the settings entry needs ssh_config_import', (t) async {
    final s = await signedInState(
      t,
      harness: SyncHarness(capabilities: const ['sync']),
    );
    await pumpApp(
      t,
      state: s,
      child: const SettingsScreen(initialGroup: 'data'),
    );
    await pumpReal(t, rounds: 5);
    expect(find.byKey(const Key('settings-import-ssh-config')), findsNothing);
  });
}
