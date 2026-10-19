// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/design/seal.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/ssh/jump_connector.dart';
import 'package:unfeudal_client/src/ssh/ssh_connector.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'support/fakes.dart';
import 'support/pump_app.dart';
import 'support/sync_harness.dart';

Future<(AppState, FakeSshConnector, FakeDialogs)> home() async {
  final h = SyncHarness();
  await h.createAccount(testEmail, testPassword);
  final ssh = FakeSshConnector()
    ..keyType = 'ssh-ed25519'
    ..fingerprint = 'SHA256:${'A' * 43}';
  final dialogs = FakeDialogs()..accept = true;
  final s = testAppState(harness: h, ssh: ssh)..dialogs = dialogs;
  await s.boot();
  await s.login(server: h.baseUrl, email: testEmail, password: testPassword);
  return (s, ssh, dialogs);
}

Future<String> host(
  AppState s,
  String name, {
  String? jump,
  String? folderId,
  String? user = 'root',
  List<Map<String, Object?>>? forwards,
}) => s.vault!.upsertItem(
  type: 'host',
  folderId: folderId,
  meta: {
    ...hostJson(name, address: '$name.lan', user: user),
    'jumpHostId': ?jump,
    'forwards': ?forwards,
  },
);

FolderMeta jumpFolder(String jump) => FolderMeta.fromJson({
  'schemaVersion': 1,
  'name': 'prod',
  'defaults': {
    'port': null,
    'user': null,
    'identityId': null,
    'jumpHostId': jump,
  },
});

void main() {
  group('jump hosts', () {
    test('a folder-default bastion: each hop checked with its own id, JumpUsed before ConnectSucceeded', () async {
      final (s, ssh, dialogs) = await home();
      final bastion = await host(s, 'bastion', user: 'jump');
      final prod = await s.vault!.saveFolder(jumpFolder(bastion));
      final web = await host(s, 'web', folderId: prod);
      final events = <AppEvent>[];
      s.events.listen(events.add);
      final tab = await s.connect(web);
      expect(tab.state, SealState.connected);
      expect(ssh.targets.map((t) => (t.hostId, t.user)), [
        (bastion, 'jump'),
        (web, 'root'),
      ]);
      expect(dialogs.checks.map((c) => c.hostId), [bastion, web]);
      expect(ssh.hops.first.forwarded, ['web.lan:22']);
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<JumpUsed>().single.hopIds, [bastion]);
      expect(
        events.indexWhere((e) => e is JumpUsed),
        lessThan(events.indexWhere((e) => e is ConnectSucceeded)),
      );
    });

    test('a changed bastion key stops the chain before the target', () async {
      final (s, ssh, dialogs) = await home();
      final bastion = await host(s, 'bastion');
      final web = await host(s, 'web', jump: bastion);
      await s.vault!.pinHostKey(bastion, 'ssh-ed25519', 'SHA256:${'B' * 43}');
      dialogs.accept = false;
      final tab = await s.connect(web);
      expect(ssh.targets.map((t) => t.hostId), [bastion]);
      expect(dialogs.checks.single.decision, HostKeyDecision.changed);
      expect(
        tab.error,
        isA<JumpChainFailed>().having((e) => e.hostName, 'hostName', 'bastion'),
      );
      expect(
        tab.state,
        SealState.offline,
      ); // the target's own key is not in question
    });

    test(
      'loop, missing and too-deep chains fail before any connection',
      () async {
        final (s, ssh, _) = await home();
        final a = await host(s, 'a');
        final b = await host(s, 'b', jump: a);
        await s.vault!.upsertItem(
          id: a,
          type: 'host',
          meta: {
            ...hostJson('a', address: 'a.lan', user: 'root'),
            'jumpHostId': b,
          },
        );
        expect((await s.connect(a)).error, isA<JumpLoop>());
        final gone = await host(s, 'gone');
        final c = await host(s, 'c', jump: gone);
        await s.vault!.trashItem(gone);
        expect((await s.connect(c)).error, isA<JumpHostMissing>());
        expect(
          (await s.connect(await host(s, 'd', jump: newId()))).error,
          isA<JumpHostMissing>(),
        );
        var prev = await host(s, 'h0');
        for (var i = 1; i <= 9; i++) {
          prev = await host(s, 'h$i', jump: prev);
        }
        expect((await s.connect(prev)).error, isA<JumpTooDeep>());
        expect(ssh.targets, isEmpty);
      },
    );

    test('a bastion without a user fails as that hop', () async {
      final (s, ssh, _) = await home();
      final bastion = await host(s, 'bastion', user: null);
      final tab = await s.connect(await host(s, 'web', jump: bastion));
      expect(
        tab.error,
        isA<JumpChainFailed>().having(
          (e) => e.cause,
          'cause',
          isA<MissingUser>(),
        ),
      );
      expect(ssh.targets, isEmpty);
    });

    test('closing the tab closes every hop', () async {
      final (s, ssh, _) = await home();
      final bastion = await host(s, 'bastion');
      final tab = await s.connect(await host(s, 'web', jump: bastion));
      await s.closeTab(tab);
      expect(ssh.hops.map((h) => h.closed), [true, true]);
    });
  });
}
