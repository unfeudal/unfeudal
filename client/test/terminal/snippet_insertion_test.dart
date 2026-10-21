// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/terminal/snippet_insertion.dart';
import 'package:unfeudal_client/src/terminal/terminal_session.dart';

import '../support/fakes.dart';

(TerminalSession, FakeShell) live() {
  final shell = FakeShell();
  return (TerminalSession(hostId: 'h', title: 'web')..attach(shell), shell);
}

String last(FakeShell s) => utf8.decode(s.written.last);
Future<bool> never() async => fail('no confirmation expected');

void main() {
  test('one line goes in without Enter and without asking', () async {
    final (tab, shell) = live();
    expect(await insertSnippet(tab, 'df -h\n\n', confirm: never), isTrue);
    expect(last(shell), 'df -h');
  });

  test('control characters are removed, so an embedded end-of-paste marker cannot escape', () async {
    final (tab, shell) = live();
    // The remote turns bracketed paste on.
    tab.terminal.write('\x1b[?2004h');
    expect(
      await insertSnippet(
        tab,
        'echo a\x1b[201~\x07\r\nrm -rf /tmp/x\n',
        confirm: never,
      ),
      isTrue,
    );
    expect(last(shell), '\x1b[200~echo a[201~\nrm -rf /tmp/x\x1b[201~');
  });

  test(
    'multi-line without bracketed paste asks; cancel sends nothing',
    () async {
      final (tab, shell) = live();
      final before = shell.written.length;
      expect(
        await insertSnippet(tab, 'cd /srv\nmake\n', confirm: () async => false),
        isFalse,
      );
      expect(shell.written.length, before);
      expect(
        await insertSnippet(tab, 'cd /srv\nmake\n', confirm: () async => true),
        isTrue,
      );
      // Paste sends a line break as a carriage return.
      expect(last(shell), 'cd /srv\rmake');
    },
  );

  test(
    'a tab that is not connected, or text that cleans to nothing, gets nothing',
    () async {
      expect(
        await insertSnippet(
          TerminalSession(hostId: 'h', title: 'x'),
          'ls',
          confirm: never,
        ),
        isFalse,
      );
      final (tab, shell) = live();
      final before = shell.written.length;
      expect(await insertSnippet(tab, '\x1b\n\n', confirm: never), isFalse);
      expect(shell.written.length, before);
    },
  );
}
