// SPDX-License-Identifier: Apache-2.0
import '../design/seal.dart';
import 'terminal_session.dart';

final _unsafe = RegExp(
  r'[\x00-\x08\x0B-\x1F\x7F-\x9F]',
); // C0 and C1 except \t and \n

/// Sends [text] to [tab] as typed input, never followed by Enter. Multi-line text without
/// bracketed paste needs [confirm]. Returns whether anything was sent.
Future<bool> insertSnippet(
  TerminalSession tab,
  String text, {
  required Future<bool> Function() confirm,
}) async {
  if (tab.state != SealState.connected) return false;
  final clean = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(
        _unsafe,
        '',
      ) // ESC gone: an embedded "\x1b[201~" cannot close the bracketed paste
      .replaceFirst(RegExp(r'\n+$'), ''); // never ends with Enter
  if (clean.isEmpty) return false;
  if (clean.contains('\n') &&
      !tab.terminal.bracketedPasteMode &&
      !await confirm()) {
    return false;
  }
  tab.terminal.paste(
    clean,
  ); // wrapped in 200~/201~ when the remote enabled bracketed paste
  return true;
}
