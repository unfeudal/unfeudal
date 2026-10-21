// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/api/api_client.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/session/session_store.dart';
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
  test('boot: a stored session goes to unlock', () async {
    final (h, s, kv, mirrors) = await loggedIn();
    final again = testAppState(harness: h, kv: kv, mirrors: mirrors);
    await again.boot();
    expect(again.stage, AppStage.unlock);
  });

  test('boot: no session goes to login', () async {
    final fresh = testAppState(harness: SyncHarness());
    await fresh.boot();
    expect(fresh.stage, AppStage.login);
  });

  test(
    'boot: a newer mirror goes to a blocking stage, nothing wiped',
    () async {
      final (h, s, kv, _) = await loggedIn();
      final tooNew = AppState(
        sessions: s.sessions,
        settingsStore: s.settingsStore,
        openMirror: (_) async => throw const MirrorTooNew(2),
        httpClient: h.client,
        kdfFloor: KdfParams.testing,
        kdf: KdfParams.testing,
      );
      await tooNew.boot();
      expect(tooNew.stage, AppStage.mirrorTooNew);
      expect(kv.values, isNotEmpty);
    },
  );

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
    // 53 base32 characters in groups of 4.
    expect(s.recoveryKey!.replaceAll('-', ''), hasLength(53));
    final bundle =
        jsonDecode(s.mirror!.kv(KvKey.bundle)!) as Map<String, Object?>;
    expect(bundle['bundleVersion'], 0);
    s.finishOnboarding();
    expect((s.stage, s.recoveryKey), (AppStage.home, null));
    expect(s.stored!.isInstanceOwner, isTrue);
    // The device is named after its OS, never the hostname.
    expect([
      'Windows',
      'macOS',
      'Linux',
    ], contains(h.devices.values.single.name));
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
      expect((await s.checkServer(lan)).has(Flag.plainHttpLan), isTrue);
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
    // The harness uses KdfParams.testing, below the floor in production.
    await h.createAccount(email, password);
    final s = AppState(
      sessions: SessionStore(FakeSecureKv()),
      settingsStore: FakeSettingsStore(),
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
      (s.stage, s.signedOutBecause, h.devices.values.single.revokedAt),
      (AppStage.home, null, null),
    );
  });

  test('lock wipes the key, entries and terminal tabs', () async {
    final (h, s, _, _) = await loggedIn();
    await s.vault!.upsertItem(
      type: 'host',
      meta: hostJson('web', user: 'root'),
    );
    final shell = FakeShell();
    s.connections.tabs.add(
      TerminalSession(hostId: 'x', title: 'x')..attach(shell),
    );
    await s.lock();
    expect(s.vault!.isUnlocked, false);
    expect(s.vault!.entries, isEmpty);
    expect(s.connections.tabs, isEmpty);
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

  test('device_revoked goes to login, mirror and outbox kept', () async {
    final (h, s, _, mirrors) = await loggedIn();
    h.offline = true;
    await s.vault!.upsertItem(type: 'host', meta: hostJson('web'));
    h.offline = false;
    h.devices.values.first.revokedAt = h.now;
    await s.sync!.syncNow();
    // The session ends behind the sync round.
    await pumpEventQueue();
    expect(
      (s.stage, s.signedOutBecause),
      (AppStage.login, SignOutReason.deviceRevoked),
    );
    expect(mirrors.values.single.outbox(), hasLength(1));
    final kept = (await s.sessions.load())!;
    expect((kept.refreshToken, kept.email), (null, s.stored!.email));
  });

  test(
    'a relaunch after device_revoked skips the unlock and goes to login',
    () async {
      final (h, s, _, _) = await loggedIn();
      h.devices.values.first.revokedAt = h.now;
      await s.sync!.syncNow();
      await pumpEventQueue();
      await s.boot();
      expect(s.stage, AppStage.login);
    },
  );

  test('session_expired goes to login and forgets the refresh token', () async {
    final (h, s, _, _) = await loggedIn();
    h.expireSessions();
    await s.sync!.syncNow();
    await pumpEventQueue();
    expect(
      (s.stage, s.signedOutBecause),
      (AppStage.login, SignOutReason.sessionExpired),
    );
    expect((await s.sessions.load())!.refreshToken, isNull);
  });

  test(
    'invite: a new account from an enrollment lands on the setup stage',
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

  test('invite: an email that already has an account is refused with account_exists', () async {
    final h = SyncHarness();
    await h.createAccount('owner@example.org', 'password-000');
    final token = b64(List.filled(32, 5));
    h.invites[token] = 'owner@example.org';
    final s = testAppState(harness: h);
    await s.boot();
    await expectLater(
      s.acceptInvite(
        enrollment: Enrollment(h.baseUrl, token, EnrollKind.invite),
        email: 'owner@example.org',
        password: 'password-456',
      ),
      throwsA(
        isA<ApiException>().having(
          (e) => e.conflictReason,
          'conflictReason',
          ConflictReason.accountExists,
        ),
      ),
    );
  });

  test('recovery kit regeneration bumps the bundle version', () async {
    final (h, s, _, _) = await loggedIn();
    await s.credentials.regenerateRecoveryKit(password);
    expect(h.accounts[email]!.bundleVersion, 1);
    final bundle =
        jsonDecode(s.mirror!.kv(KvKey.bundle)!) as Map<String, Object?>;
    expect(bundle['bundleVersion'], 1);
  });

  test(
    'recovery with the key returns a new key and revokes every device',
    () async {
      final (h, s, _, _) = await loggedIn();
      final fresh = await s.credentials.regenerateRecoveryKit(password);
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
    },
  );

  test('after a recovery the new password signs in', () async {
    final (h, s, _, _) = await loggedIn();
    final fresh = await s.credentials.regenerateRecoveryKit(password);
    final other = testAppState(harness: h);
    await other.boot();
    await other.recover(
      server: h.baseUrl,
      email: email,
      recoveryKey: fresh,
      newPassword: 'new-password-1',
    );
    await other.login(
      server: h.baseUrl,
      email: email,
      password: 'new-password-1',
    );
    expect(other.stage, AppStage.home);
  });
}
