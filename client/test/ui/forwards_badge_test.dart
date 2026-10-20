// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/terminal/terminal_session.dart';
import 'package:unfeudal_client/src/ui/shell/home_shell.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';

void main() {
  testWidgets(
    'badge: active count, start and stop from the popover, failures shown',
    (t) async {
      final ssh = FakeSshConnector()
        ..keyType = 'ssh-ed25519'
        ..fingerprint = 'SHA256:${'A' * 43}';
      final s = await signedInState(t, ssh: ssh);
      late int port1, port2;
      late ServerSocket blocker;
      late TerminalSession tab;
      await t.runAsync(() async {
        port1 = await freePort();
        blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        port2 = blocker.port;
        final web = await s.vault!.upsertItem(
          type: 'host',
          meta: {
            ...hostJson('web', user: 'root'),
            'forwards': [
              {
                'localPort': port1,
                'remoteHost': 'db',
                'remotePort': 5432,
                'autoStart': true,
              },
              {
                'localPort': port2,
                'remoteHost': 'cache',
                'remotePort': 6379,
                'autoStart': false,
              },
            ],
          },
        );
        await s.vault!.hostKeys.pin(web, 'ssh-ed25519', 'SHA256:${'A' * 43}');
        tab = await s.connections.connect(web);
      });
      await pumpApp(t, state: s);
      await pumpReal(t, rounds: 5);
      final l = AppLocalizations.of(t.element(find.byType(HomeShell)));
      final badge = find.byKey(const Key('forwards-badge-0'));
      expect(
        find.descendant(of: badge, matching: find.text('1')),
        findsOneWidget,
      );
      expect(find.byTooltip(l.forwardsActive(1)), findsOneWidget);
      await t.tap(badge);
      await t.pumpAndSettle();
      expect(find.text('127.0.0.1:$port1 → db:5432'), findsOneWidget);
      await t.tap(find.byKey(Key('forward-start-$port2')));
      await pumpReal(t, rounds: 5);
      expect(find.text(l.errorPortInUse(port2)), findsOneWidget);
      await t.tap(find.byKey(Key('forward-stop-$port1')));
      await pumpReal(t, rounds: 5);
      expect(tab.forwarder!.active, isEmpty);
      await t.runAsync(blocker.close);
      await t.runAsync(() => s.connections.closeTab(tab));
    },
  );

  testWidgets('a host without forwards has no badge', (t) async {
    final ssh = FakeSshConnector()
      ..keyType = 'ssh-ed25519'
      ..fingerprint = 'SHA256:${'A' * 43}';
    final s = await signedInState(t, ssh: ssh);
    await t.runAsync(() async {
      final web = await s.vault!.upsertItem(
        type: 'host',
        meta: hostJson('web', user: 'root'),
      );
      await s.vault!.hostKeys.pin(web, 'ssh-ed25519', 'SHA256:${'A' * 43}');
      await s.connections.connect(web);
    });
    await pumpApp(t, state: s);
    await pumpReal(t, rounds: 5);
    expect(find.byKey(const Key('forwards-badge-0')), findsNothing);
  });
}
