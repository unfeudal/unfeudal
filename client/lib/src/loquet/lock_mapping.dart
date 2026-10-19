// SPDX-License-Identifier: Apache-2.0
import '../session/lock_machine.dart';
import 'line_bank.dart';
import 'loquet_pose.dart';

/// Loquet's face and line for each state of the access screens.
({LoquetMood mood, LineKey? line}) loquetForLock(
  LockScreenState s,
) => switch (s) {
  LockScreenState.locked => (mood: LoquetMood.idle, line: null),
  LockScreenState.email => (mood: LoquetMood.watching, line: null),
  LockScreenState.password => (
    mood: LoquetMood.covering,
    line: LineKey.notLooking,
  ),
  LockScreenState.peek => (mood: LoquetMood.peeking, line: LineKey.peeking),
  LockScreenState.checking => (
    mood: LoquetMood.connecting,
    line: LineKey.checking,
  ),
  LockScreenState.error => (mood: LoquetMood.sad, line: LineKey.wrongPassword),
  LockScreenState.success => (mood: LoquetMood.happy, line: LineKey.welcome),
  LockScreenState.hello => (
    mood: LoquetMood.watching,
    line: LineKey.waitingHello,
  ),
  LockScreenState.asleep => (mood: LoquetMood.sleep, line: null),
};
