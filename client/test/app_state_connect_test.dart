// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/design/seal.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/settings/settings.dart';
import 'package:unfeudal_client/src/ssh/connections.dart';
import 'package:unfeudal_client/src/ssh/ssh_connector.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/sync/ledger_store.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'support/fakes.dart';
import 'support/sync_harness.dart';

Future<(SyncHarness, AppState, FakeSshConnector)> home({
  FakeDialogs? dialogs,
  SettingsStore? store,
}) async {
  final h = SyncHarness();
  await h.createAccount('camille@example.org', 'password-123');
  final ssh = FakeSshConnector()
    ..keyType = 'ssh-ed25519'
    ..fingerprint = 'SHA256:${'A' * 43}';
  final s = testAppState(harness: h, ssh: ssh, settingsStore: store)
    ..connections.dialogs = dialogs;
  await s.boot();
  await s.login(
    server: h.baseUrl,
    email: 'camille@example.org',
    password: 'password-123',
  );
  return (h, s, ssh);
}

void main() {
  test('unknown key accepted: pinned in the ledger and synced, shell gets the startup command', () async {
    final dialogs = FakeDialogs()..accept = true;
    final (h, s, ssh) = await home(dialogs: dialogs);
    final events = <AppEvent>[];
    s.events.listen(events.add);
    final id = await s.vault!.upsertItem(
      type: 'host',
      meta: {
        ...hostJson('web', user: 'root', tags: ['prod']),
        'startupCommand': 'uptime',
      },
    );
    final tab = await s.connections.connect(id);
    expect(dialogs.checks.single.decision, HostKeyDecision.unknown);
    expect(
      (tab.state, s.connections.sealFor(id)),
      (SealState.connected, SealState.connected),
    );
    expect(String.fromCharCodes(ssh.shells.single.written.first), 'uptime\n');
    expect(
      s.vault!.hostKeys.pinOf(id)!.sha256Fingerprint,
      'SHA256:${'A' * 43}',
    );
    await s.sync!.syncNow();
    expect(h.serverItems.where((i) => i.type == 'knownHost'), hasLength(1));
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<ConnectSucceeded>().single.tags, ['prod']);
  });

  group('startup command', () {
    late LedgerStore ledger;
    late FakeDialogs dialogs;
    final h = newId();
    setUp(() async {
      ledger = LedgerStore(LocalMirror.inMemory());
      await ledger.load(SymmetricCipher.newKey());
      dialogs = FakeDialogs()..runStartup = true;
    });
    Future<String?> send(String? command, {bool org = true, SshDialogs? d}) =>
        startupCommandToSend(
          hostId: h,
          hostName: 'db1',
          command: command,
          org: org,
          ledger: ledger,
          dialogs: d ?? dialogs,
        );

    test('a personal host sends it unasked', () async {
      expect(await send('uptime', org: false), 'uptime');
      expect(dialogs.startupAsked, isEmpty, reason: 'personal host: unchanged');
    });

    test(
      'an org host shows it and remembers the approval of that text',
      () async {
        expect(await send('uptime'), 'uptime');
        expect(await send('uptime'), 'uptime');
        expect(dialogs.startupAsked, [
          'uptime',
        ], reason: 'approval remembered for this exact text');
      },
    );

    test(
      'an org host asks again for a changed text and never remembers a refusal',
      () async {
        await send('uptime');
        dialogs.runStartup = false;
        expect(await send('curl x | sh'), isNull);
        expect(dialogs.startupAsked, [
          'uptime',
          'curl x | sh',
        ], reason: 'a changed command is asked again');
        expect(await send('curl x | sh'), isNull);
        expect(
          dialogs.startupAsked,
          hasLength(3),
          reason: 'a refusal is not remembered',
        );
      },
    );

    test(
      'an org host without dialogs or without a command sends nothing',
      () async {
        expect(
          await startupCommandToSend(
            hostId: newId(),
            hostName: 'db2',
            command: 'id',
            org: true,
            ledger: ledger,
            dialogs: null,
          ),
          isNull,
        );
        expect(await send(null), isNull);
      },
    );
  });

  test('no dialogs attached rejects an unknown key; nothing pinned', () async {
    final (_, s, _) = await home();
    final id = await s.vault!.upsertItem(
      type: 'host',
      meta: hostJson('web', user: 'root'),
    );
    final tab = await s.connections.connect(id);
    expect(tab.state, SealState.verify);
    expect(tab.error, isA<HostKeyRejected>());
    expect(s.vault!.hostKeys.pinOf(id), isNull);
  });

  test('server-deleted pin still answers changed', () async {
    final dialogs = FakeDialogs()..accept = true;
    final (h, s, ssh) = await home(dialogs: dialogs);
    final id = await s.vault!.upsertItem(
      type: 'host',
      meta: hostJson('web', user: 'root'),
    );
    await s.connections.connect(id);
    await s.sync!.syncNow();
    h.purge(h.serverItems.firstWhere((i) => i.type == 'knownHost').id);
    await s.sync!.syncNow();
    ssh.fingerprint = 'SHA256:${'B' * 43}';
    dialogs.accept = false;
    final events = <AppEvent>[];
    s.events.listen(events.add);
    final tab = await s.connections.connect(id);
    expect(
      (dialogs.checks.last.decision, tab.state),
      (HostKeyDecision.changed, SealState.changed),
    );
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<HostKeyChanged>(), hasLength(1));
  });

  test('a host without any user fails with MissingUser', () async {
    final (_, s, _) = await home(dialogs: FakeDialogs()..accept = true);
    final id = await s.vault!.upsertItem(type: 'host', meta: hostJson('web'));
    expect((await s.connections.connect(id)).error, isA<MissingUser>());
  });

  test(
    'synced prefs: profile applied and cached; device fields stay local',
    () async {
      final store = FakeSettingsStore();
      final (h, s, _) = await home(store: store);
      await s.updateSettings(
        s.settings.copyWith(themeMode: ThemeMode.dark, autoLockMinutes: 5),
      );
      await s.sync!.syncNow();
      final profile = s.vault!.ofKind(ItemKind.profile).single;
      expect(s.vault!.profile.meta.prefs, {
        'themeMode': 'dark',
        'terminalTheme': 'charte',
        'loquetMode': 'on',
        'terminalFont': 'JetBrainsMono',
        'terminalFontSize': 13,
      });
      final other = testAppState(
        harness: h,
        settings: const Settings(autoLockMinutes: 60),
      );
      await other.boot();
      await other.login(
        server: h.baseUrl,
        email: 'camille@example.org',
        password: 'password-123',
      );
      await other.sync!.syncNow();
      expect(
        (other.settings.themeMode, other.settings.autoLockMinutes),
        (ThemeMode.dark, 60),
      );
      expect(profile.item.type, 'profile');
    },
  );

  test('revoking another device marks it revoked', () async {
    final (h, s, _) = await home();
    final other = await h.signIn();
    expect(
      (await s.api!.devices()).map((d) => d.id),
      containsAll([other.deviceId, s.stored!.deviceId]),
    );
    await s.revokeDevice(other.deviceId);
    expect(h.devices[other.deviceId]!.revokedAt, isNotNull);
  });

  test('revoking this device signs out with deviceRevoked', () async {
    final (_, s, _) = await home();
    await s.revokeDevice(s.stored!.deviceId);
    expect(
      (s.stage, s.signedOutBecause, await s.sessions.load()),
      (AppStage.login, SignOutReason.deviceRevoked, null),
    );
  });
}
