// SPDX-License-Identifier: Apache-2.0
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/loquet/line_bank.dart';
import 'package:unfeudal_client/src/loquet/loquet_controller.dart';
import 'package:unfeudal_client/src/loquet/loquet_memory.dart';
import 'package:unfeudal_client/src/loquet/loquet_pose.dart';
import 'package:unfeudal_client/src/loquet/reaction_engine.dart';
import 'package:unfeudal_client/src/settings/settings.dart';

void main() {
  late DateTime now;
  LoquetController make() {
    now = DateTime(2026, 10, 15, 12);
    return LoquetController(
      ReactionEngine(memory: LoquetMemory(), now: () => now),
    );
  }

  test(
    'a reaction shows, its bubble ends after 3 s, its mood after its hold',
    () {
      fakeAsync((async) {
        final c = make()..attach();
        c.show(
          const Reaction(
            LoquetMood.happy,
            line: LineKey.connected,
            hold: Duration(seconds: 5),
          ),
        );
        expect((c.mood, c.line), (LoquetMood.happy, LineKey.connected));
        async.elapse(const Duration(seconds: 3));
        expect((c.mood, c.line), (LoquetMood.happy, null));
        async.elapse(const Duration(seconds: 2));
        expect(c.mood, LoquetMood.cheerful);
        c.detach();
      });
    },
  );

  test('an important bubble lasts 6 s', () {
    fakeAsync((async) {
      final c = make()..attach();
      c.show(
        const Reaction(
          LoquetMood.happy,
          line: LineKey.firstHost,
          important: true,
        ),
      );
      async.elapse(const Duration(seconds: 5));
      expect(c.line, LineKey.firstHost);
      async.elapse(const Duration(seconds: 1));
      expect(c.line, isNull);
      c.detach();
    });
  });

  test('a grave reaction holds; lesser ones queue behind it', () {
    fakeAsync((async) {
      final c = make()..attach();
      c.show(
        const Reaction(
          LoquetMood.alert,
          line: LineKey.keyChanged,
          important: true,
        ),
      );
      c.show(const Reaction(LoquetMood.happy, line: LineKey.connected));
      expect((c.mood, c.line), (LoquetMood.alert, LineKey.keyChanged));
      async.elapse(const Duration(seconds: 6));
      expect((c.mood, c.line), (LoquetMood.happy, LineKey.connected));
      c.show(
        const Reaction(
          LoquetMood.offline,
          line: LineKey.offline,
          spontaneous: true,
        ),
      );
      // A grave mood replaces a lesser one at once.
      expect(c.mood, LoquetMood.offline);
      c.detach();
    });
  });

  test('timers run only while a spot is attached; the reaction survives', () {
    fakeAsync((async) {
      final c = make()..attach();
      c.show(const Reaction(LoquetMood.happy, line: LineKey.connected));
      c.detach();
      async.elapse(const Duration(minutes: 5));
      expect(c.line, LineKey.connected);
      expect(async.pendingTimers, isEmpty);
      c.attach();
      async.elapse(const Duration(seconds: 3));
      expect(c.line, isNull);
      c.detach();
    });
  });

  test('the minute tick reaches the engine while attached', () {
    fakeAsync((async) {
      final c = make();
      now = DateTime(2026, 10, 16, 1, 59, 30);
      c.attach();
      async.elapse(const Duration(minutes: 1));
      expect((c.mood, c.line), (LoquetMood.sleepy, LineKey.night));
      c.detach();
    });
  });

  test('a serious mood hides the session accessory', () {
    fakeAsync((async) {
      final c = make()..attach();
      c.show(
        c.engine.handle(
          const ConnectSucceeded(hostId: 'h', user: 'root', tags: []),
        ),
      );
      expect(c.accessory, LoquetAccessory.hardHat);
      c.show(c.engine.handle(const HostKeyChanged()));
      expect((c.mood, c.accessory), (LoquetMood.alert, null));
      c.detach();
    });
  });

  test('mode: off hides Loquet; every change notifies', () {
    final c = make();
    var n = 0;
    c.addListener(() => n++);
    c.mode = LoquetMode.off;
    expect((c.visible, c.engine.mode, n), (false, LoquetMode.off, 1));
    c.show(
      c.engine.handle(const ConnectSucceeded(hostId: 'h', user: 'u', tags: [])),
    );
    expect(c.line, isNull);
  });

  test('watch: eyes follow input for a moment', () {
    fakeAsync((async) {
      final c = make()..attach();
      c.watch(0.8);
      expect((c.mood, c.eyeX), (LoquetMood.watching, 0.8));
      async.elapse(const Duration(seconds: 2));
      expect(c.mood, LoquetMood.cheerful);
      c.detach();
    });
  });
}
