// SPDX-License-Identifier: Apache-2.0
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/session/auto_lock.dart';

void main() {
  test('locks after the idle timeout; activity restarts it; idle event after 5 min once', () {
    fakeAsync((async) {
      var locks = 0, idles = 0;
      final a = AutoLock(
        timeout: () => const Duration(minutes: 15),
        onLock: () => locks++,
        onIdle: () => idles++,
      )..start();
      async.elapse(const Duration(minutes: 10));
      a.activity();
      async.elapse(const Duration(minutes: 14));
      expect((locks, idles), (0, 2));
      async.elapse(const Duration(minutes: 1));
      expect(locks, 1);
      expect(a.running, isFalse);
    });
  });

  test('zero never locks; stop cancels', () {
    fakeAsync((async) {
      var locks = 0;
      AutoLock(timeout: () => Duration.zero, onLock: () => locks++).start();
      async.elapse(const Duration(hours: 5));
      expect(locks, 0);
      final b = AutoLock(
        timeout: () => const Duration(minutes: 5),
        onLock: () => locks++,
      )..start();
      b.stop();
      async.elapse(const Duration(hours: 1));
      expect(locks, 0);
    });
  });
}
