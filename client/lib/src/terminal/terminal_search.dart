// SPDX-License-Identifier: Apache-2.0
import 'package:xterm2/xterm.dart';

/// A hit in the buffer: line `y` (scrollback included), cells `x` to `x + length`.
typedef TerminalMatch = ({int y, int x, int length});

/// Every non-overlapping, case-insensitive hit of [query], top to bottom; a hit never spans two lines.
List<TerminalMatch> findInTerminal(Terminal terminal, String query) {
  if (query.isEmpty) return const [];
  final needle = query.toLowerCase();
  final hits = <TerminalMatch>[];
  for (final (y, line) in terminal.buffer.lines.toList().indexed) {
    final (text, cells) = _lowerTextWithCells(line);
    for (final m in needle.allMatches(text)) {
      final first = cells[m.start], last = cells[m.end - 1];
      hits.add((y: y, x: first, length: last + line.getWidth(last) - first));
    }
  }
  return hits;
}

// The line's text in lower case and, for each of its UTF-16 units, the cell it is drawn in: a wide character takes two
// cells, so string indexes and columns part after one. Combining marks are left out of the text.
(String, List<int>) _lowerTextWithCells(BufferLine line) {
  final text = StringBuffer();
  final cells = <int>[];
  for (var cell = 0; cell < line.length; cell++) {
    final codePoint = line.getCodePoint(cell);
    if (codePoint == 0) continue;
    // Lowered one character at a time: lowering can lengthen it, and the cells must follow.
    final char = String.fromCharCode(codePoint).toLowerCase();
    text.write(char);
    cells.addAll(List.filled(char.length, cell));
  }
  return (text.toString(), cells);
}
