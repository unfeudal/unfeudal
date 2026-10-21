// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/design/seal.dart';
import 'package:unfeudal_client/src/terminal/terminal_session.dart';

import '../support/fakes.dart';

void main() {
  test('output reaches the terminal; input, resize and startup command reach the shell', () async {
    final shell = FakeShell();
    var inputs = 0;
    final s = TerminalSession(hostId: 'h', title: 'web')
      ..onUserInput = () => inputs++;
    s.attach(shell, startupCommand: 'tmux attach');
    expect(utf8.decode(shell.written.single), 'tmux attach\n');
    shell.emit('hello');
    await Future<void>.delayed(Duration.zero);
    expect(s.terminal.buffer.getText(), contains('hello'));
    s.terminal.textInput('ls');
    expect((utf8.decode(shell.written.last), inputs), ('ls', 1));
    s.terminal.resize(100, 30);
    expect(shell.sizes.last, (100, 30));
    expect(s.state, SealState.connected);
  });

  test('hang-up marks the tab offline; close closes the shell', () async {
    final shell = FakeShell();
    final s = TerminalSession(hostId: 'h', title: 'web')..attach(shell);
    shell.hangUp();
    await Future<void>.delayed(Duration.zero);
    expect(s.state, SealState.offline);
    await s.close();
    expect(shell.closed, isTrue);
  });
}
