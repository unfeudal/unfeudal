// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/design/seal.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/ssh/jump_connector.dart';
import 'package:unfeudal_client/src/ssh/port_forwarder.dart';
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
  final s = testAppState(harness: h, ssh: ssh)..connections.dialogs = dialogs;
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
      final tab = await s.connections.connect(web);
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
      await s.vault!.hostKeys.pin(bastion, 'ssh-ed25519', 'SHA256:${'B' * 43}');
      dialogs.accept = false;
      final tab = await s.connections.connect(web);
      expect(ssh.targets.map((t) => t.hostId), [bastion]);
      expect(dialogs.checks.single.decision, HostKeyDecision.changed);
      expect(
        tab.error,
        isA<JumpChainFailed>().having((e) => e.hostName, 'hostName', 'bastion'),
      );
      // The target's own key is not in question.
      expect(tab.state, SealState.offline);
    });

    test('a jump loop fails before any connection', () async {
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
      expect((await s.connections.connect(a)).error, isA<JumpLoop>());
      expect(ssh.targets, isEmpty);
    });

    test('a trashed jump host fails before any connection', () async {
      final (s, ssh, _) = await home();
      final gone = await host(s, 'gone');
      final c = await host(s, 'c', jump: gone);
      await s.vault!.trashItem(gone);
      expect((await s.connections.connect(c)).error, isA<JumpHostMissing>());
      expect(ssh.targets, isEmpty);
    });

    test('an unknown jump host id fails before any connection', () async {
      final (s, ssh, _) = await home();
      expect(
        (await s.connections.connect(await host(s, 'd', jump: newId()))).error,
        isA<JumpHostMissing>(),
      );
      expect(ssh.targets, isEmpty);
    });

    test('a too-deep jump chain fails before any connection', () async {
      final (s, ssh, _) = await home();
      var prev = await host(s, 'h0');
      for (var i = 1; i <= 9; i++) {
        prev = await host(s, 'h$i', jump: prev);
      }
      expect((await s.connections.connect(prev)).error, isA<JumpTooDeep>());
      expect(ssh.targets, isEmpty);
    });

    test('a bastion without a user fails as that hop', () async {
      final (s, ssh, _) = await home();
      final bastion = await host(s, 'bastion', user: null);
      final tab = await s.connections.connect(
        await host(s, 'web', jump: bastion),
      );
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
      final tab = await s.connections.connect(
        await host(s, 'web', jump: bastion),
      );
      await s.connections.closeTab(tab);
      expect(ssh.hops.map((h) => h.closed), [true, true]);
    });
  });

  group('forwards', () {
    Map<String, Object?> f(int port, String remote, {bool auto = false}) => {
      'localPort': port,
      'remoteHost': remote,
      'remotePort': 5432,
      'autoStart': auto,
    };

    test('autoStart forwards start with the session over the target hop; the others wait', () async {
      final (s, ssh, _) = await home();
      final port1 = await freePort(), port2 = await freePort();
      final web = await host(
        s,
        'web',
        forwards: [f(port1, 'db.internal', auto: true), f(port2, 'cache')],
      );
      final events = <AppEvent>[];
      s.events.listen(events.add);
      final tab = await s.connections.connect(web);
      expect(tab.forwarder!.active.keys, [port1]);
      final client = await Socket.connect(InternetAddress.loopbackIPv4, port1);
      await ssh.hops.single.firstForward.timeout(const Duration(seconds: 5));
      expect(ssh.hops.single.forwarded, ['db.internal:5432']);
      client.destroy();
      await s.connections.startForward(
        tab,
        s.vault!.hostLookup(web)!.meta.forwards[1],
      );
      expect(tab.forwarder!.active.keys, unorderedEquals([port1, port2]));
      await s.connections.stopForward(tab, port1);
      await Future<void>.delayed(Duration.zero);
      expect(
        events.whereType<ForwardStarted>().map((e) => e.forward.localPort),
        [port1, port2],
      );
      expect(events.whereType<ForwardStopped>().map((e) => e.localPort), [
        port1,
      ]);
    });

    test('a port in use: not started, the session stays connected', () async {
      final (s, _, _) = await home();
      final blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final events = <AppEvent>[];
      s.events.listen(events.add);
      final tab = await s.connections.connect(
        await host(s, 'web', forwards: [f(blocker.port, 'db', auto: true)]),
      );
      expect(tab.state, SealState.connected);
      expect(tab.forwarder!.failed[blocker.port], isA<PortInUse>());
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<ForwardStarted>(), isEmpty);
      await blocker.close();
    });

    test(
      'closing the tab and locking stop every forward and report it',
      () async {
        final (s, _, _) = await home();
        final p = await freePort();
        final web = await host(s, 'web', forwards: [f(p, 'db', auto: true)]);
        final events = <AppEvent>[];
        s.events.listen(events.add);
        await s.connections.closeTab(await s.connections.connect(web));
        await Future<void>.delayed(Duration.zero);
        expect(events.whereType<ForwardStopped>().single.localPort, p);
        await (await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          p,
        )).close();
        final again = await s.connections.connect(web);
        await s.lock();
        expect(again.forwarder!.active, isEmpty);
        await (await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          p,
        )).close();
      },
    );
  });

  test(
    'reconnect closes the previous session first and keeps the tab position',
    () async {
      final (s, ssh, _) = await home();
      final a = await s.connections.connect(await host(s, 'a'));
      final b = await s.connections.connect(await host(s, 'b'));
      ssh.shells.first.hangUp();
      await Future<void>.delayed(Duration.zero);
      final again = await s.connections.reconnect(a);
      expect(s.connections.tabs, [again, b]);
      expect(s.connections.activeTab, 0);
      expect(again.state, SealState.connected);
      expect(ssh.hops.first.closed, isTrue);
    },
  );

  test(
    'moving a tab reorders the tabs and keeps the shown one shown',
    () async {
      final (s, _, _) = await home();
      final a = await s.connections.connect(await host(s, 'a'));
      final b = await s.connections.connect(await host(s, 'b'));
      final c = await s.connections.connect(await host(s, 'c'));
      s.connections.selectTab(1);
      s.connections.moveTab(2, 0);
      expect(s.connections.tabs, [c, a, b]);
      expect(s.connections.activeSession, b);
    },
  );

  test('AppState emits SessionClosed once per connected tab: closed, ended by the host, or locked', () async {
    final h = SyncHarness(capabilities: ['client_events', 'sync']);
    await h.createAccount('camille@example.org', 'password-123');
    final ssh = FakeSshConnector()
      ..keyType = 'ssh-ed25519'
      ..fingerprint = 'SHA256:${'A' * 43}';
    final AppState s = testAppState(harness: h, ssh: ssh)
      ..connections.dialogs = (FakeDialogs()..accept = true);
    await s.boot();
    await s.login(
      server: h.baseUrl,
      email: 'camille@example.org',
      password: 'password-123',
    );
    final closed = <String>[];
    s.events.listen((e) {
      if (e is SessionClosed) closed.add(e.hostId);
    });
    final [a, b, c] = [
      for (final n in ['a', 'b', 'c'])
        await s.vault!.upsertItem(
          type: 'host',
          meta: hostJson(n, user: 'root'),
        ),
    ];
    await s.sync!.syncNow();
    await s.connections.closeTab(await s.connections.connect(a));
    await s.connections.connect(b);
    ssh.shells.last.hangUp();
    await Future<void>.delayed(Duration.zero);
    await s.connections.connect(c);
    await Future.sync(s.lock);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(closed, [a, b, c]);
    expect(h.reported.where((r) => r.body['event'] == 'close'), hasLength(3));
  });
}
