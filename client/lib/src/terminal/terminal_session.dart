// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:xterm2/xterm.dart';

import '../debug_trace.dart';
import '../design/seal.dart';
import '../ssh/jump_connector.dart';
import '../ssh/ssh_connector.dart';

/// One terminal tab. What the shell prints only goes to the terminal: never stored or inspected.
class TerminalSession extends ChangeNotifier {
  TerminalSession({required this.hostId, required this.title});

  final String hostId;
  final String title;
  final terminal = Terminal(maxLines: 10000);
  SealState state = SealState.connecting;
  Object? error;
  VoidCallback? onUserInput;

  /// The hops and the target behind [_shell].
  JumpConnection? connection;
  SshShell? _shell;
  final _subscriptions = <StreamSubscription<String>>[];

  void attach(SshShell shell, {String? startupCommand}) {
    _shell = shell;
    for (final stream in [shell.stdout, shell.stderr]) {
      _subscriptions.add(
        const Utf8Decoder(allowMalformed: true)
            .bind(stream)
            .listen(terminal.write),
      );
    }
    terminal
      ..onOutput = (data) {
        shell.write(utf8.encode(data));
        onUserInput?.call();
      }
      ..onResize = (cols, rows, _, _) => shell.resize(cols, rows);
    if (startupCommand != null) shell.write(utf8.encode('$startupCommand\n'));
    state = SealState.connected;
    notifyListeners();
    unawaited(
      shell.done.then((_) {
        trace(TraceArea.ssh, 'shell closed ${shortId(hostId)}');
        fail(null);
      }),
    );
  }

  void fail(Object? error, {SealState state = SealState.offline}) {
    this.error = error;
    this.state = state;
    notifyListeners();
  }

  Future<void> close() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _shell?.close();
    await connection?.close();
  }
}
