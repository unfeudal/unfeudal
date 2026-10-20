// SPDX-License-Identifier: Apache-2.0
import '../design/seal.dart';
import 'terminal_session.dart';

// C0 and C1 control characters except \t and \n.
final _unsafe = RegExp(r'[\x00-\x08\x0B-\x1F\x7F-\x9F]');

/// Sends [text] to [tab] as typed input, never followed by Enter. Multi-line text without
/// bracketed paste needs [confirm]. Returns whether anything was sent.
Future<bool> insertSnippet(
  TerminalSession tab,
  String text, {
  required Future<bool> Function() confirm,
}) async {
  if (tab.state != SealState.connected) return false;
  // Without ESC, an embedded "\x1b[201~" cannot close the bracketed paste; the text never ends with Enter.
  final clean = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(_unsafe, '')
      .replaceFirst(RegExp(r'\n+$'), '');
  if (clean.isEmpty) return false;
  if (clean.contains('\n') &&
      !tab.terminal.bracketedPasteMode &&
      !await confirm()) {
    return false;
  }
  // Wrapped in 200~/201~ when the remote enabled bracketed paste.
  tab.terminal.paste(clean);
  return true;
}
