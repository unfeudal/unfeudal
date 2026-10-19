// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/loquet/line_bank.dart';
import 'package:unfeudal_client/src/loquet/lock_mapping.dart';
import 'package:unfeudal_client/src/loquet/loquet_pose.dart';
import 'package:unfeudal_client/src/session/lock_machine.dart';

void main() {
  test('each lock screen state has its face and line', () {
    expect(
      {for (final s in LockScreenState.values) s: loquetForLock(s)},
      {
        LockScreenState.locked: (mood: LoquetMood.idle, line: null),
        LockScreenState.email: (mood: LoquetMood.watching, line: null),
        LockScreenState.password: (
          mood: LoquetMood.covering,
          line: LineKey.notLooking,
        ),
        LockScreenState.peek: (mood: LoquetMood.peeking, line: LineKey.peeking),
        LockScreenState.checking: (
          mood: LoquetMood.connecting,
          line: LineKey.checking,
        ),
        LockScreenState.error: (
          mood: LoquetMood.sad,
          line: LineKey.wrongPassword,
        ),
        LockScreenState.success: (
          mood: LoquetMood.happy,
          line: LineKey.welcome,
        ),
        LockScreenState.hello: (
          mood: LoquetMood.watching,
          line: LineKey.waitingHello,
        ),
        LockScreenState.asleep: (mood: LoquetMood.sleep, line: null),
      },
    );
  });
}
