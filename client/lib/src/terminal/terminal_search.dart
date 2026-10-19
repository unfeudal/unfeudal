// SPDX-License-Identifier: Apache-2.0
import 'package:xterm2/xterm.dart';

/// A hit in the buffer: line [y] (scrollback included), from string index [x].
typedef TerminalMatch = ({int y, int x, int length});

/// Every non-overlapping, case-insensitive hit of [query], top to bottom; a hit never spans two lines.
// ponytail: x is a string index; a line with wide (CJK) cells shifts the highlight, map through the cell width if it matters
List<TerminalMatch> findInTerminal(Terminal terminal, String query) {
  if (query.isEmpty) return const [];
  final needle = query.toLowerCase();
  final lines = terminal.buffer.lines;
  return [
    for (var y = 0; y < lines.length; y++)
      for (final m in needle.allMatches(lines[y].getText().toLowerCase()))
        (y: y, x: m.start, length: needle.length),
  ];
}
