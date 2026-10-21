// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/ui/shell/home_shell.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';

void main() {
  testWidgets(
    'badge: active count, start and stop from the popover, failures shown',
    (t) async {
      late int port1, port2;
      late ServerSocket blocker;
      await t.runAsync(() async {
        port1 = await freePort();
        blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        port2 = blocker.port;
      });
      final (s, tab, _) = await pinnedTab(
        t,
        hostMeta: {
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
      final l = AppLocalizations.of(t.element(find.byType(HomeShell)));
      final badge = find.byKey(const Key('forwards-badge-0'));
      expect(
        find.descendant(of: badge, matching: find.text('1')),
        findsOneWidget,
      );
      expect(find.byTooltip(l.forwardsActive(1)), findsOneWidget);
      await t.tap(badge);
      await t.pumpAndSettle();
      expect(
        find.text(l.forwardRoute('127.0.0.1:$port1', 'db:5432')),
        findsOneWidget,
      );
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
    await pinnedTab(t);
    expect(find.byKey(const Key('forwards-badge-0')), findsNothing);
  });
}
