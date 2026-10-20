// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/settings/settings.dart';
import 'package:unfeudal_client/src/ui/settings/settings_screen.dart';
import 'package:xterm2/xterm.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';

void main() {
  testWidgets('font and size are synced prefs', (t) async {
    final s = await signedInState(t);
    await pumpApp(t, state: s, child: const SettingsScreen());
    await t.ensureVisible(find.byKey(const Key('terminal-font')));
    await t.pump();
    await t.tap(find.byKey(const Key('terminal-font-size')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('terminal-font-size-16')).last);
    await pumpReal(t, rounds: 5);
    await t.tap(find.byKey(const Key('terminal-font')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('terminal-font-Consolas')).last);
    await pumpReal(t, rounds: 5);
    expect(
      (s.settings.terminalFont, s.settings.terminalFontSize),
      ('Consolas', 16),
    );
    expect(s.vault!.profile.meta.prefs['terminalFont'], 'Consolas');
    expect(s.vault!.profile.meta.prefs['terminalFontSize'], 16);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a synced font from another platform stays selected', (t) async {
    final s = await signedInState(
      t,
      settings: const Settings(terminalFont: 'Menlo'),
    );
    await pumpApp(t, state: s, child: const SettingsScreen());
    await t.ensureVisible(find.byKey(const Key('terminal-font')));
    await t.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('terminal-font')),
        matching: find.text('Menlo'),
      ),
      findsOneWidget,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('open terminals use the font settings', (t) async {
    final ssh = FakeSshConnector()
      ..keyType = 'ssh-ed25519'
      ..fingerprint = 'SHA256:${'A' * 43}';
    final s = await signedInState(
      t,
      ssh: ssh,
      settings: const Settings(terminalFont: 'Menlo', terminalFontSize: 16),
    );
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
    final style = t.widget<TerminalView>(find.byType(TerminalView)).textStyle;
    expect((style.fontFamily, style.fontSize), ('Menlo', 16.0));
  });
}
