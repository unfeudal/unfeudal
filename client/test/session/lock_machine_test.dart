// SPDX-License-Identifier: Apache-2.0
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/session/lock_machine.dart';

void main() {
  test('password flow: typing, peek, checking, error, retry, success', () {
    final m = LockMachine();
    final seen = <LockScreenState>[];
    m.addListener(() => seen.add(m.state));
    m
      ..focusPassword()
      ..togglePeek()
      ..togglePeek()
      ..submit()
      ..fail()
      ..input()
      ..submit()
      ..succeed();
    expect(seen, [
      LockScreenState.password,
      LockScreenState.peek,
      LockScreenState.password,
      LockScreenState.checking,
      LockScreenState.error,
      LockScreenState.password,
      LockScreenState.checking,
      LockScreenState.success,
    ]);
  });

  test('illegal transitions are ignored', () {
    final m = LockMachine();
    m
      ..submit()
      ..succeed()
      ..togglePeek();
    expect(m.state, LockScreenState.locked);
    m
      ..focusEmail()
      ..submit();
    expect(m.state, LockScreenState.email);
  });

  test('hello goes to success or back to locked', () {
    final m = LockMachine()..helloStarted();
    expect(m.state, LockScreenState.hello);
    m.helloCancelled();
    expect(m.state, LockScreenState.locked);
    m
      ..helloStarted()
      ..succeed();
    expect(m.state, LockScreenState.success);
  });

  test(
    'locked falls asleep after 20 s of idle while watched, wakes on input',
    () {
      fakeAsync((async) {
        final m = LockMachine()..startIdleWatch();
        async.elapse(const Duration(seconds: 19));
        expect(m.state, LockScreenState.locked);
        async.elapse(const Duration(seconds: 1));
        expect(m.state, LockScreenState.asleep);
        m.input();
        expect(m.state, LockScreenState.locked);
        m
          ..focusPassword()
          ..stopIdleWatch();
        async.elapse(const Duration(minutes: 5));
        expect(m.state, LockScreenState.password);
      });
    },
  );

  test('events are plain values', () {
    const AppEvent e = HostCreated(hostId: 'h', name: 'localhost', total: 42);
    expect(switch (e) {
      HostCreated(:final total) => total,
      _ => 0,
    }, 42);
    expect(
      const ConnectSucceeded(hostId: 'h', user: 'root', tags: ['prod']).user,
      'root',
    );
  });
}
