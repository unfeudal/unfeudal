// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/terminal/terminal_search.dart';
import 'package:xterm2/xterm.dart';

void main() {
  test('every hit, case-insensitive, scrollback included, top to bottom', () {
    final t = Terminal();
    for (var i = 0; i < 100; i++) {
      t.write('line $i\r\n');
    }
    t.write('Alpha beta ALPHA');
    final hits = findInTerminal(t, 'alpha');
    expect(hits.map((m) => (m.x, m.length)), [(0, 5), (11, 5)]);
    expect(hits.first.y, hits.last.y);
    // Long scrolled out of the 24-row viewport.
    expect(findInTerminal(t, 'line 0').single.y, 0);
    expect(findInTerminal(t, ''), isEmpty);
    expect(findInTerminal(t, 'zzz'), isEmpty);
  });

  test(
    'a hit after wide characters is placed by cell, not by string index',
    () {
      final t = Terminal()..write('日本 abc 語x');
      expect(findInTerminal(t, 'abc').single, (y: 0, x: 5, length: 3));
      expect(findInTerminal(t, '語x').single, (y: 0, x: 9, length: 3));
    },
  );

  test('a character that grows when lowered keeps the next hits in place', () {
    final t = Terminal()..write('İ abc');
    expect(findInTerminal(t, 'abc').single, (y: 0, x: 2, length: 3));
  });
}
