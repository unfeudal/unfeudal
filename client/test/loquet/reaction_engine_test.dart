// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/loquet/line_bank.dart';
import 'package:unfeudal_client/src/loquet/loquet_memory.dart';
import 'package:unfeudal_client/src/loquet/loquet_pose.dart';
import 'package:unfeudal_client/src/loquet/reaction_engine.dart';
import 'package:unfeudal_client/src/settings/settings.dart';

const ok = ConnectSucceeded(hostId: 'h', user: 'deploy', tags: []);
const asRoot = ConnectSucceeded(hostId: 'h', user: 'root', tags: []);

void main() {
  late DateTime now;
  late ReactionEngine e;
  setUp(() {
    now = DateTime(2026, 10, 15, 12); // Thursday, local
    e = ReactionEngine(memory: LoquetMemory(), now: () => now);
  });

  test('off yields nothing; counters still count', () {
    e.mode = LoquetMode.off;
    expect(e.handle(ok), isNull);
    expect(e.tick(), isNull);
    expect(e.memory.connections, 1);
  });

  test('sober keeps the mood and drops the line', () {
    e.mode = LoquetMode.sober;
    final r = e.handle(ok)!;
    expect((r.mood, r.line), (LoquetMood.happy, null));
  });

  test('sober disables easter eggs entirely', () {
    e.mode = LoquetMode.sober;
    final r = e.handle(asRoot)!;
    expect((r.accessory, r.line), (null, null));
    expect(e.sessionAccessory, isNull);
    now = DateTime(2026, 12, 25, 12);
    expect(e.sessionAccessory, isNull);
  });

  test('one spontaneous bubble per 10 minutes; direct answers are exempt', () {
    expect(e.handle(const WentOffline())!.line, LineKey.offline);
    e.handle(const CameOnline());
    now = now.add(const Duration(minutes: 9));
    final again = e.handle(const WentOffline())!;
    expect((again.mood, again.line), (LoquetMood.offline, null));
    expect(e.handle(ok)!.line, LineKey.connected);
    e.handle(const CameOnline());
    now = now.add(const Duration(minutes: 1));
    expect(e.handle(const WentOffline())!.line, LineKey.offline);
  });

  test(
    'no spontaneous bubble while typing in a terminal; the clock line waits',
    () {
      now = DateTime(2026, 10, 16, 2, 10);
      e.terminalInput();
      expect(e.typing, isTrue);
      expect(e.tick(), isNull);
      now = now.add(const Duration(seconds: 4));
      expect(e.typing, isFalse);
      final r = e.tick()!;
      expect(
        (r.mood, r.line, r.spontaneous),
        (LoquetMood.sleepy, LineKey.night, true),
      );
      expect(e.tick(), isNull); // once per night
    },
  );

  test(
    'while typing, even a direct answer keeps its face and loses its bubble',
    () {
      e.terminalInput();
      final r = e.handle(const HostKeyChanged(hostId: 'h'))!;
      expect((r.mood, r.line), (LoquetMood.alert, null));
      now = now.add(const Duration(seconds: 4));
      expect(
        e.handle(const HostKeyChanged(hostId: 'h'))!.line,
        LineKey.keyChanged,
      );
    },
  );

  test('serious moods never wear an accessory', () {
    now = DateTime(2026, 4, 1, 12);
    e.handle(asRoot);
    final r = e.handle(const HostKeyChanged(hostId: 'h'))!;
    expect(
      (r.mood, r.accessory, r.line, r.important),
      (LoquetMood.alert, null, LineKey.keyChanged, true),
    );
  });

  test('baseline: offline over dozing over concerned over night', () {
    expect(e.baseline, LoquetMood.cheerful);
    now = DateTime(2026, 10, 16, 1);
    expect(e.baseline, LoquetMood.sleepy);
    e.handle(const UserIdle());
    expect(e.baseline, LoquetMood.sleep);
    e.handle(const WentOffline());
    expect(e.baseline, LoquetMood.offline);
    e.handle(const CameOnline());
    expect(e.wake()!.mood, LoquetMood.sleepy);
    expect(e.wake(), isNull);
  });

  test('snippet and forward events get no reaction', () {
    expect(e.handle(const SnippetInserted(snippetId: 's')), isNull);
    expect(
      e.handle(const ForwardStopped(hostId: 'h', localPort: 8080)),
      isNull,
    );
  });
}
