// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/terminal/terminal_search.dart';
import 'package:xterm2/xterm.dart';

void main() {
  test('every hit, case-insensitive, scrollback included, top to bottom', () {
    final t = Terminal(maxLines: 1000);
    for (var i = 0; i < 100; i++) {
      t.write('line $i\r\n');
    }
    t.write('Alpha beta ALPHA');
    final hits = findInTerminal(t, 'alpha');
    expect(hits.map((m) => (m.x, m.length)), [(0, 5), (11, 5)]);
    expect(hits.first.y, hits.last.y);
    expect(
      findInTerminal(t, 'line 0').single.y,
      0,
    ); // long scrolled out of the 24-row viewport
    expect(findInTerminal(t, ''), isEmpty);
    expect(findInTerminal(t, 'zzz'), isEmpty);
  });
}
