// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/design/seal.dart';
import 'package:unfeudal_client/src/terminal/terminal_session.dart';
import 'package:unfeudal_client/src/ui/terminal/terminal_pane.dart';
import 'package:xterm2/xterm.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';

final windows = TargetPlatformVariant.only(TargetPlatform.windows);

Future<(AppState, TerminalSession, FakeSshConnector)> open(
  WidgetTester t,
) async {
  final opened = await pinnedTab(t);
  await t.tap(find.byType(TerminalView));
  await t.pump();
  return opened;
}

Future<void> chord(
  WidgetTester t,
  LogicalKeyboardKey key, {
  bool shift = true,
}) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(key);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pumpAndSettle();
}

void clipboard(
  WidgetTester t, {
  List<String?>? copied,
  String Function()? paste,
}) => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
  SystemChannels.platform,
  (call) async {
    if (call.method == 'Clipboard.setData') {
      copied?.add((call.arguments as Map)['text'] as String?);
    }
    if (call.method == 'Clipboard.getData') return {'text': paste?.call()};
    return null;
  },
);

void main() {
  testWidgets(
    'plain Ctrl+C reaches the shell; Ctrl+Shift+C copies the selection',
    (t) async {
      final copied = <String?>[];
      clipboard(t, copied: copied);
      final (_, tab, ssh) = await open(t);
      tab.terminal.write('hello world');
      await chord(t, LogicalKeyboardKey.keyC, shift: false);
      expect(utf8.decode(ssh.shells.single.written.last), '\x03');
      tab.controller.setSelection(
        tab.terminal.buffer.createAnchor(0, 0),
        tab.terminal.buffer.createAnchor(5, 0),
      );
      await chord(t, LogicalKeyboardKey.keyC);
      expect(copied, ['hello']);
    },
    variant: windows,
  );

  testWidgets('paste: a single line goes straight in', (t) async {
    clipboard(t, paste: () => 'ls -la\n');
    final (_, _, ssh) = await open(t);
    await chord(t, LogicalKeyboardKey.keyV);
    expect(utf8.decode(ssh.shells.single.written.last), 'ls -la');
  }, variant: windows);

  testWidgets('paste: multi-line asks first and cancel sends nothing', (
    t,
  ) async {
    clipboard(t, paste: () => 'rm a\nrm b');
    final (_, _, ssh) = await open(t);
    final shell = ssh.shells.single;
    final before = shell.written.length;
    await chord(t, LogicalKeyboardKey.keyV);
    await t.tap(find.byKey(const Key('multiline-cancel')));
    await t.pumpAndSettle();
    expect(shell.written.length, before);
  }, variant: windows);

  testWidgets('paste: bracketed paste does not ask', (t) async {
    clipboard(t, paste: () => 'rm a\nrm b');
    final (_, tab, ssh) = await open(t);
    tab.terminal.write('\x1b[?2004h');
    await chord(t, LogicalKeyboardKey.keyV);
    expect(find.byKey(const Key('multiline-cancel')), findsNothing);
    expect(
      utf8.decode(ssh.shells.single.written.last),
      '\x1b[200~rm a\nrm b\x1b[201~',
    );
  }, variant: windows);

  testWidgets('right-click menu pastes', (t) async {
    clipboard(t, paste: () => 'uptime');
    final (_, _, ssh) = await open(t);
    await t.tap(find.byType(TerminalView), buttons: kSecondaryButton);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('term-menu-copy')), findsOneWidget);
    await t.tap(find.byKey(const Key('term-menu-paste')));
    await t.pumpAndSettle();
    expect(utf8.decode(ssh.shells.single.written.last), 'uptime');
  }, variant: windows);

  testWidgets(
    'search: count from the latest hit, next and previous wrap, Escape clears',
    (t) async {
      final (_, tab, _) = await open(t);
      final l = AppLocalizations.of(t.element(find.byType(TerminalPane)));
      tab.terminal.write('alpha\r\nbeta\r\nalpha\r\nALPHA');
      await chord(t, LogicalKeyboardKey.keyF);
      await t.enterText(find.byKey(const Key('term-search-input')), 'alpha');
      await t.pump();
      expect(find.text(l.termSearchCount(3, 3)), findsOneWidget);
      expect(tab.controller.highlights, hasLength(3));
      await t.tap(find.byKey(const Key('term-search-next')));
      await t.pump();
      expect(find.text(l.termSearchCount(1, 3)), findsOneWidget);
      await t.tap(find.byKey(const Key('term-search-prev')));
      await t.pump();
      expect(find.text(l.termSearchCount(3, 3)), findsOneWidget);
      await t.enterText(find.byKey(const Key('term-search-input')), 'zzz');
      await t.pump();
      expect(find.text(l.termSearchNone), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('term-search-input')), findsNothing);
      expect(tab.controller.highlights, isEmpty);
    },
    variant: windows,
  );

  testWidgets('after a hang-up the banner reconnects', (t) async {
    final (s, _, ssh) = await open(t);
    final l = AppLocalizations.of(t.element(find.byType(TerminalPane)));
    ssh.shells.single.hangUp();
    // The hang-up runs in the real zone.
    await pumpReal(t, rounds: 3);
    expect(find.text(l.termClosed), findsOneWidget);
    await t.tap(find.byKey(const Key('term-reconnect')));
    await pumpReal(t, rounds: 5);
    expect(s.connections.tabs.single.state, SealState.connected);
    expect(ssh.shells, hasLength(2));
  }, variant: windows);

  testWidgets('Ctrl+Shift+R reconnects after a hang-up', (t) async {
    final (s, _, ssh) = await open(t);
    ssh.shells.single.hangUp();
    // The hang-up runs in the real zone.
    await pumpReal(t, rounds: 3);
    await t.tap(find.byType(TerminalView));
    await chord(t, LogicalKeyboardKey.keyR);
    await pumpReal(t, rounds: 5);
    expect(s.connections.tabs.single.state, SealState.connected);
    expect(ssh.shells, hasLength(2));
  }, variant: windows);
}
