// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/design/seal.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/settings/settings.dart';
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
    ..dialogs = dialogs;
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
    final tab = await s.connect(id);
    expect(dialogs.checks.single.decision, HostKeyDecision.unknown);
    expect(
      (tab.state, s.sealFor(id)),
      (SealState.connected, SealState.connected),
    );
    expect(String.fromCharCodes(ssh.shells.single.written.first), 'uptime\n');
    expect(s.vault!.trustedPin(id)!.sha256Fingerprint, 'SHA256:${'A' * 43}');
    await s.sync!.syncNow();
    expect(h.serverItems.where((i) => i.type == 'knownHost'), hasLength(1));
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<ConnectSucceeded>().single.tags, ['prod']);
  });

  test('org host: startup command shown and approved once per text; refused or no dialogs → not sent', () async {
    final ledger = LedgerStore(LocalMirror.inMemory());
    await ledger.load(SymmetricCipher.newKey());
    final dialogs = FakeDialogs()..runStartup = true;
    final h = newId();
    Future<String?> send(String? command, {bool org = true, SshDialogs? d}) =>
        startupCommandToSend(
          hostId: h,
          hostName: 'db1',
          command: command,
          org: org,
          ledger: ledger,
          dialogs: d ?? dialogs,
        );
    expect(await send('uptime', org: false), 'uptime');
    expect(dialogs.startupAsked, isEmpty, reason: 'personal host: unchanged');
    expect(await send('uptime'), 'uptime');
    expect(await send('uptime'), 'uptime');
    expect(dialogs.startupAsked, [
      'uptime',
    ], reason: 'approval remembered for this exact text');
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
  });

  test('no dialogs attached rejects an unknown key; nothing pinned', () async {
    final (_, s, _) = await home();
    final id = await s.vault!.upsertItem(
      type: 'host',
      meta: hostJson('web', user: 'root'),
    );
    final tab = await s.connect(id);
    expect(tab.state, SealState.verify);
    expect(tab.error, isA<HostKeyRejected>());
    expect(s.vault!.trustedPin(id), isNull);
  });

  test('server-deleted pin still answers changed', () async {
    final dialogs = FakeDialogs()..accept = true;
    final (h, s, ssh) = await home(dialogs: dialogs);
    final id = await s.vault!.upsertItem(
      type: 'host',
      meta: hostJson('web', user: 'root'),
    );
    await s.connect(id);
    await s.sync!.syncNow();
    h.purge(h.serverItems.firstWhere((i) => i.type == 'knownHost').id);
    await s.sync!.syncNow();
    ssh.fingerprint = 'SHA256:${'B' * 43}';
    dialogs.accept = false;
    final events = <AppEvent>[];
    s.events.listen(events.add);
    final tab = await s.connect(id);
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
    expect((await s.connect(id)).error, isA<MissingUser>());
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
      expect(s.vault!.profile.prefs, {
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

  test('devices: list, revoke another, revoking this one signs out', () async {
    final (h, s, _) = await home();
    final other = await h.signIn();
    expect(
      (await s.loadDevices()).map((d) => d.id),
      containsAll([other.deviceId, s.stored!.deviceId]),
    );
    await s.revokeDevice(other.deviceId);
    expect(h.devices[other.deviceId]!.revokedAt, isNotNull);
    await s.revokeDevice(s.stored!.deviceId);
    expect(
      (s.stage, s.deviceRevoked, await s.sessions.load()),
      (AppStage.login, true, null),
    );
  });
}
