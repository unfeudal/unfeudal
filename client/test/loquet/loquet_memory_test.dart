// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/loquet/loquet_memory.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('loquet'));
  tearDown(() => dir.deleteSync(recursive: true));
  final now = DateTime(2026, 10, 15, 12);

  test('file holds exactly v, counters, firstUnlock and sorted once', () async {
    final f = File('${dir.path}/loquet.json');
    final m = await LoquetMemory.load(f, now: now);
    m
      ..connections = 3
      ..hostsCreated = 2
      ..firstUnlock = DateTime.utc(2026, 1, 2, 3)
      ..fire('night:2026-10-15')
      ..fire('firstHost');
    await m.save();
    final json = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    expect(json, {
      'v': 1,
      'connections': 3,
      'hostsCreated': 2,
      'firstUnlock': '2026-01-02T03:00:00.000Z',
      'once': ['firstHost', 'night:2026-10-15'],
    });
    expect(File('${f.path}.tmp').existsSync(), isFalse);
  });

  test('round-trips; period keys older than 7 days are pruned', () async {
    final f = File('${dir.path}/loquet.json')
      ..writeAsStringSync(
        jsonEncode({
          'v': 1,
          'connections': 99,
          'hostsCreated': 41,
          'firstUnlock': null,
          'once': [
            'connections100',
            'night:2026-10-01',
            'night:2026-10-10',
            'yawn:2026-10-15',
          ],
        }),
      );
    final m = await LoquetMemory.load(f, now: now);
    expect((m.connections, m.hostsCreated, m.firstUnlock), (99, 41, null));
    expect(m.hasFired('connections100'), isTrue);
    expect(m.hasFired('night:2026-10-01'), isFalse);
    expect(m.hasFired('night:2026-10-10'), isTrue);
    expect(m.hasFired('yawn:2026-10-15'), isTrue);
  });

  test('unreadable or unknown version gives defaults', () async {
    for (final text in [
      '{',
      '[]',
      '{"v": 2, "connections": 5}',
      '{"v": 1, "connections": "x"}',
    ]) {
      final f = File('${dir.path}/loquet.json')..writeAsStringSync(text);
      final m = await LoquetMemory.load(f, now: now);
      expect(
        (m.connections, m.hostsCreated, m.firstUnlock, m.hasFired('firstHost')),
        (0, 0, null, false),
      );
    }
    final missing = await LoquetMemory.load(
      File('${dir.path}/none.json'),
      now: now,
    );
    expect(missing.connections, 0);
  });

  test('in memory: no file, save is a no-op', () async {
    final m = LoquetMemory()..fire('a');
    await m.save();
    expect(m.hasFired('a'), isTrue);
  });
}
