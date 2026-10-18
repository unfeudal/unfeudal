// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/session/session_store.dart';
import 'package:unfeudal_client/src/settings/settings.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/terminal/terminal_session.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'support/fakes.dart';
import 'support/sync_harness.dart';

const email = 'camille@example.org', password = 'password-123';

Future<(SyncHarness, AppState, FakeSecureKv, Map<String, LocalMirror>)>
loggedIn() async {
  final h = SyncHarness();
  await h.createAccount(email, password);
  final kv = FakeSecureKv();
  final mirrors = <String, LocalMirror>{};
  final s = testAppState(harness: h, kv: kv, mirrors: mirrors);
  await s.boot();
  await s.login(server: h.baseUrl, email: email, password: password);
  return (h, s, kv, mirrors);
}

void main() {
  test('boot: no session → login; a session → unlock; a newer mirror → blocking stage, nothing wiped', () async {
    final (h, s, kv, mirrors) = await loggedIn();
    expect(s.stage, AppStage.home);
    final again = testAppState(harness: h, kv: kv, mirrors: mirrors);
    await again.boot();
    expect(again.stage, AppStage.unlock);
    final fresh = testAppState(harness: h);
    await fresh.boot();
    expect(fresh.stage, AppStage.login);
    final tooNew = AppState(
      sessions: s.sessions,
      settingsStore: s.settingsStore,
      openMirror: (_) async => throw const MirrorTooNew(2),
      httpClient: h.client,
      allowTestingKdf: true,
      kdf: KdfParams.testing,
    );
    await tooNew.boot();
    expect(tooNew.stage, AppStage.mirrorTooNew);
    expect(kv.values, isNotEmpty);
  });

  test('setup: owner created, recovery key shown once, kit in kv.bundle with its version', () async {
    final h = SyncHarness();
    final s = testAppState(harness: h);
    await s.boot();
    await s.setup(
      server: h.baseUrl,
      token: 'abcd-efgh-ijkl-mnop-qrst-uvwx-yz',
      email: email,
      password: password,
      displayName: 'Camille',
    );
    expect(s.stage, AppStage.setup);
    expect(
      s.recoveryKey!.replaceAll('-', ''),
      hasLength(53),
    ); // 53 base32 characters in groups of 4
    expect(jsonDecode(s.mirror!.getKv(KvKey.bundle)!)['bundleVersion'], 0);
    s.finishOnboarding();
    expect((s.stage, s.recoveryKey), (AppStage.home, null));
    expect(s.stored!.isInstanceOwner, isTrue);
    expect([
      'Windows',
      'macOS',
      'Linux',
    ], contains(h.devices.values.single.name)); // never the hostname
  });

  test(
    "http server needs a LAN host, plain_http_lan and the user's confirmation",
    () async {
      final h = SyncHarness(capabilities: ['sync']);
      final s = testAppState(harness: h);
      final lan = Uri.parse('http://192.168.1.10:8080');
      await expectLater(
        s.checkServer(Uri.parse('http://vault.example.org')),
        throwsA(isA<InsecureServer>()),
      );
      await expectLater(s.checkServer(lan), throwsA(isA<InsecureServer>()));
      h.capabilities = ['plain_http_lan', 'sync'];
      await expectLater(
        s.checkServer(lan),
        throwsA(isA<PlainHttpRefused>()),
        reason: 'no one to confirm',
      );
      final asked = <Uri>[];
      s.confirmPlainHttp = (u) async {
        asked.add(u);
        return asked.length > 1;
      };
      await expectLater(s.checkServer(lan), throwsA(isA<PlainHttpRefused>()));
      expect((await s.checkServer(lan)).has('plain_http_lan'), isTrue);
      expect(asked, [lan, lan]);
      expect(
        await s.checkServer(Uri.parse('https://vault.example.org')),
        isA<ApiInfo>(),
      );
      expect(asked, hasLength(2), reason: 'https asks nothing');
    },
  );

  test('weak prelogin KDF is refused before derivation', () async {
    final h = SyncHarness();
    await h.createAccount(
      email,
      password,
    ); // KdfParams.testing: below the floor in production
    final s = AppState(
      sessions: SessionStore(FakeSecureKv()),
      settingsStore: SettingsStore.memory(),
      openMirror: (_) async => LocalMirror.inMemory(),
      httpClient: h.client,
    );
    await expectLater(
      s.login(server: h.baseUrl, email: email, password: password),
      throwsA(isA<WeakKdf>()),
    );
    expect(h.requests, isNot(contains('POST /api/v1/login')));
  });

  test(
    'unlock works offline from the cached bundle; a wrong password is counted',
    () async {
      final (h, s, kv, mirrors) = await loggedIn();
      await s.lock();
      h.offline = true;
      final events = <AppEvent>[];
      s.events.listen(events.add);
      await expectLater(
        s.unlock('wrong-password'),
        throwsA(isA<WrongPassword>()),
      );
      await s.unlock(password);
      await Future<void>.delayed(Duration.zero);
      expect(s.stage, AppStage.home);
      expect(events.whereType<UnlockFailed>().single.consecutive, 1);
      expect(events.whereType<Unlocked>(), hasLength(1));
    },
  );

  test('unlock resumes with the refresh token rotated since sign-in, not a replayed one', () async {
    final (h, s, _, _) = await loggedIn();
    h.expireAccess();
    await s.sync!.syncNow(); // rotates the refresh token
    await s.lock();
    await s.unlock(password);
    await s.sync!.syncNow();
    expect(
      (s.stage, s.deviceRevoked, h.devices.values.single.revokedAt),
      (AppStage.home, false, null),
    );
  });

  test('lock wipes the key, entries and terminal tabs', () async {
    final (h, s, _, _) = await loggedIn();
    await s.vault!.upsertItem(
      type: 'host',
      meta: hostJson('web', user: 'root'),
    );
    final shell = FakeShell();
    s.tabs.add(TerminalSession(hostId: 'x', title: 'x')..attach(shell));
    await s.lock();
    expect(s.vault!.isUnlocked, false);
    expect(s.vault!.entries, isEmpty);
    expect(s.tabs, isEmpty);
    expect(s.stage, AppStage.unlock);
    expect(shell.closed, isTrue);
  });

  test('refresh rotation is persisted to the keystore', () async {
    final (h, s, kv, _) = await loggedIn();
    final before = (await s.sessions.load())!.refreshToken;
    h.expireAccess();
    await s.sync!.syncNow();
    expect((await s.sessions.load())!.refreshToken, isNot(before));
  });

  test(
    'device_revoked and session_expired go to login, mirror and outbox kept',
    () async {
      final (h, s, _, mirrors) = await loggedIn();
      h.offline = true;
      await s.vault!.upsertItem(type: 'host', meta: hostJson('web'));
      h.offline = false;
      h.devices.values.first.revokedAt = h.now;
      await s.sync!.syncNow();
      expect(
        (s.stage, s.deviceRevoked, s.sessionExpired),
        (AppStage.login, true, false),
      );
      expect(mirrors.values.single.outbox(), hasLength(1));
      final (h2, s2, _, _) = await loggedIn();
      h2.expireSessions();
      await s2.sync!.syncNow();
      expect(
        (s2.stage, s2.deviceRevoked, s2.sessionExpired),
        (AppStage.login, false, true),
      );
    },
  );

  test(
    'invite: new account from an enrollment; existing account → account_exists',
    () async {
      final h = SyncHarness();
      await h.createAccount('owner@example.org', 'password-000');
      final token = b64(List.filled(32, 5));
      h.invites[token] = 'dom@example.org';
      final s = testAppState(harness: h);
      await s.boot();
      await s.acceptInvite(
        enrollment: Enrollment(h.baseUrl, token, EnrollKind.invite),
        email: 'dom@example.org',
        password: 'password-456',
      );
      expect((s.stage, s.stored!.isInstanceOwner), (AppStage.setup, false));
    },
  );

  test('recovery kit regeneration and recovery with the key', () async {
    final (h, s, _, _) = await loggedIn();
    final fresh = await s.regenerateRecoveryKit(password);
    expect(h.accounts[email]!.bundleVersion, 1);
    expect(jsonDecode(s.mirror!.getKv(KvKey.bundle)!)['bundleVersion'], 1);
    final other = testAppState(harness: h);
    await other.boot();
    final next = await other.recover(
      server: h.baseUrl,
      email: email,
      recoveryKey: fresh,
      newPassword: 'new-password-1',
    );
    expect(next, isNot(fresh));
    expect(other.stage, AppStage.login);
    expect(h.devices.values.every((d) => d.revokedAt != null), isTrue);
    await other.login(
      server: h.baseUrl,
      email: email,
      password: 'new-password-1',
    );
    expect(other.stage, AppStage.home);
  });
}
