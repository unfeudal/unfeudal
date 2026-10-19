// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/design/logo.dart';
import 'package:unfeudal_client/src/loquet/loquet.dart';
import 'package:unfeudal_client/src/loquet/loquet_pose.dart';
import 'package:unfeudal_client/src/loquet/mood.dart';
import 'package:unfeudal_client/src/settings/settings.dart';
import 'package:unfeudal_client/src/ui/settings/settings_screen.dart';
import 'package:unfeudal_client/src/ui/terminal/terminal_tabs.dart';

import '../support/pump_app.dart';
import '../support/sync_harness.dart';

Loquet loquetIn(WidgetTester t, String key) => t.widget<Loquet>(
  find.descendant(of: find.byKey(Key(key)), matching: find.byType(Loquet)),
);

void main() {
  testWidgets('unlock: covering while typing, sad on a wrong password', (
    t,
  ) async {
    final s = await signedInState(t);
    await t.runAsync(s.lock);
    await pumpApp(t, state: s);
    expect(loquetIn(t, 'loquet-spot-lock').size, 260);
    await t.tap(find.byKey(const Key('unlock-password')));
    await t.pump();
    expect(loquetIn(t, 'loquet-spot-lock').mood, LoquetMood.covering);
    expect(
      find.text('Not looking.').evaluate().length +
          find.text('Eyes shut.').evaluate().length,
      1,
    );
    await t.enterText(find.byKey(const Key('unlock-password')), 'wrong');
    await t.tap(find.byKey(const Key('unlock-submit')));
    await pumpReal(t);
    expect(loquetIn(t, 'loquet-spot-lock').mood, LoquetMood.sad);
    expect(find.text("That's not the right password."), findsOneWidget);
  });

  testWidgets('tree card: status text, reasons on a concerned click', (
    t,
  ) async {
    final s = await signedInState(t);
    await pumpApp(t, state: s);
    expect(find.byKey(const Key('loquet-spot-tree')), findsOneWidget);
    s.loquet.setHealth(const VaultHealth(syncOver7Days: true));
    await t.pump();
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('loquet-spot-tree')),
        matching: find.byType(Loquet),
      ),
    );
    await t.pump();
    expect(find.text('No sync for over 7 days'), findsOneWidget);
  });

  testWidgets('tree hidden: Loquet moves to the rail', (t) async {
    final s = await signedInState(t);
    await pumpApp(t, state: s);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyB);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(loquetIn(t, 'loquet-spot-rail').size, 36);
  });

  testWidgets('the Konami listener wraps rail and tree, never the terminal', (
    t,
  ) async {
    final s = await signedInState(t);
    await pumpApp(t, state: s);
    final keys = find.byKey(const Key('loquet-keys'));
    expect(
      find.descendant(of: keys, matching: find.byKey(const Key('vault-rail'))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: keys, matching: find.byKey(const Key('tree-panel'))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: keys, matching: find.byType(TerminalTabs)),
      findsNothing,
    );
    await t.tap(find.byKey(const Key('tree-panel')));
    for (final k in [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.keyB,
      LogicalKeyboardKey.keyA,
    ]) {
      await t.sendKeyEvent(k);
    }
    await t.pump();
    expect(s.loquet.fx, LoquetFx.backflip);
  });

  testWidgets('empty vault shows Loquet with its line', (t) async {
    final s = await signedInState(t);
    await pumpApp(t, state: s);
    expect(find.text('Nobody to guard yet.'), findsOneWidget);
  });

  testWidgets(
    'settings: on, sober, off; forced off explains and locks the choice',
    (t) async {
      final s = await signedInState(t);
      await pumpApp(t, state: s, child: const SettingsScreen());
      await t.tap(find.byKey(const Key('loquet-mode-sober')));
      await pumpReal(t);
      expect(
        (s.settings.loquetMode, s.loquet.mode),
        (LoquetMode.sober, LoquetMode.sober),
      );

      final off = await signedInState(
        t,
        harness: SyncHarness(capabilities: const ['sync']),
      );
      await pumpApp(t, state: off, child: const SettingsScreen());
      expect(
        find.text(
          lookupAppLocalizations(const Locale('en')).settingsLoquetForcedOff,
        ),
        findsOneWidget,
      );
      expect(
        t
            .widget<ChoiceChip>(find.byKey(const Key('loquet-mode-on')))
            .onSelected,
        isNull,
      );
    },
  );

  testWidgets('off: the logo everywhere Loquet sits', (t) async {
    final s = await signedInState(
      t,
      settings: const Settings(loquetMode: LoquetMode.off),
    );
    await pumpApp(t, state: s);
    expect(find.byType(Loquet), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('loquet-spot-tree')),
        matching: find.byType(UfLogo),
      ),
      findsOneWidget,
    );
  });
}
