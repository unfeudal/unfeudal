// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/loquet/loquet_memory.dart';
import 'package:unfeudal_client/src/settings/settings.dart';
import 'package:unfeudal_client/src/terminal/terminal_session.dart';

import 'fakes.dart';
import 'sync_harness.dart';

const testEmail = 'camille@example.org', testPassword = 'password-123';

/// Pumps the whole app, or [child] inside the same theme, scopes and l10n (English unless [locale] says).
Future<AppState> pumpApp(
  WidgetTester tester, {
  AppState? state,
  Settings? settings,
  Widget? child,
  Locale locale = const Locale('en'),
}) async {
  final s = state ?? testAppState(settings: settings ?? const Settings());
  if (state == null) await tester.runAsync(s.boot);
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  await tester.pumpWidget(UnfeudalApp(state: s, locale: locale, home: child));
  await tester.pump();
  return s;
}

/// Lets real async work (crypto, mock HTTP) finish between frames.
Future<void> pumpReal(WidgetTester tester, {int rounds = 30}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
}

/// A logged-in AppState on the home stage.
Future<AppState> signedInState(
  WidgetTester tester, {
  SyncHarness? harness,
  FakeSshConnector? ssh,
  Settings settings = const Settings(),
  LoquetMemory? loquetMemory,
  DateTime Function()? loquetClock,
}) async {
  final h = harness ?? SyncHarness();
  late AppState s;
  await tester.runAsync(() async {
    if (!h.accounts.containsKey(testEmail)) {
      await h.createAccount(testEmail, testPassword);
    }
    s = testAppState(
      harness: h,
      ssh: ssh,
      settings: settings,
      loquetMemory: loquetMemory,
      loquetClock: loquetClock,
    )..confirmPlainHttp = (_) async => true;
    await s.boot();
    await s.login(server: h.baseUrl, email: testEmail, password: testPassword);
  });
  return s;
}

/// A signed-in app showing one terminal tab on host `web`, its key already pinned.
Future<(AppState, TerminalSession, FakeSshConnector)> pinnedTab(
  WidgetTester tester, {
  Settings settings = const Settings(),
  Map<String, Object?>? hostMeta,
}) async {
  const keyType = 'ssh-ed25519';
  final fingerprint = 'SHA256:${'A' * 43}';
  final ssh = FakeSshConnector()
    ..keyType = keyType
    ..fingerprint = fingerprint;
  final s = await signedInState(tester, ssh: ssh, settings: settings);
  late TerminalSession tab;
  await tester.runAsync(() async {
    final web = await s.vault!.upsertItem(
      type: 'host',
      meta: hostMeta ?? hostJson('web', user: 'root'),
    );
    await s.vault!.hostKeys.pin(web, keyType, fingerprint);
    tab = await s.connections.connect(web);
  });
  await pumpApp(tester, state: s);
  await pumpReal(tester, rounds: 5);
  return (s, tab, ssh);
}
