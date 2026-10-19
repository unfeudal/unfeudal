// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/design/seal.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'support/fakes.dart';
import 'support/pump_app.dart';
import 'support/sync_harness.dart';

void main() {
  testWidgets(
    'setup, kit, host in a folder, connect with a new key, lock, unlock offline, sync back',
    (t) async {
      final h = SyncHarness();
      final ssh = FakeSshConnector()
        ..keyType = 'ssh-ed25519'
        ..fingerprint = 'SHA256:${'D' * 43}';
      final s = await pumpApp(
        t,
        state: testAppState(harness: h, ssh: ssh)..stage = AppStage.setup,
      );
      await t.enterText(
        find.byKey(const Key('setup-server')),
        'https://vault.test',
      );
      await t.enterText(
        find.byKey(const Key('setup-token')),
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
      );
      await t.tap(find.byKey(const Key('setup-next')));
      await t.pump();
      await t.enterText(find.byKey(const Key('setup-email')), testEmail);
      await t.enterText(find.byKey(const Key('setup-password')), testPassword);
      await t.enterText(find.byKey(const Key('setup-confirm')), testPassword);
      await t.tap(find.byKey(const Key('setup-submit')));
      await pumpReal(t);
      await t.tap(find.byKey(const Key('recovery-confirm')));
      await t.pump();
      await t.tap(find.byKey(const Key('recovery-continue')));
      await pumpReal(t);
      expect(s.stage, AppStage.home);

      late String host;
      await t.runAsync(() async {
        final f = await s.vault!.saveFolder(
          FolderMeta.fromJson(folderJson('prod', user: 'deploy')),
        );
        host = await s.vault!.upsertItem(
          type: 'host',
          folderId: f,
          meta: hostJson('web'),
        );
      });
      await pumpReal(t, rounds: 10);
      await t.tap(find.byKey(Key('host-$host')));
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await pumpReal(t, rounds: 5);
      await t.tap(find.byKey(const Key('hostkey-trust')));
      await pumpReal(t, rounds: 10);
      expect(
        (s.tabs.single.state, ssh.targets.single.user),
        (SealState.connected, 'deploy'),
      );

      await t.runAsync(s.lock);
      await t.pump();
      h.offline = true;
      await t.enterText(find.byKey(const Key('unlock-password')), testPassword);
      await t.tap(find.byKey(const Key('unlock-submit')));
      await pumpReal(t);
      expect(s.stage, AppStage.home);
      await t.runAsync(
        () => s.vault!.upsertItem(type: 'host', meta: hostJson('offline-edit')),
      );
      h.offline = false;
      await t.runAsync(s.sync!.syncNow);
      expect(h.serverItems.where((i) => i.type == 'host'), hasLength(2));
      expect(h.serverItems.where((i) => i.type == 'knownHost'), hasLength(1));
      expect(h.serverItems.where((i) => i.type == 'folder'), hasLength(1));
    },
  );
}
