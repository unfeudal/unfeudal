// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/foundation.dart';

enum LockScreenState {
  locked,
  email,
  password,
  peek,
  checking,
  error,
  success,
  hello,
  asleep,
}

/// Lock screen states; an illegal transition is ignored.
class LockMachine extends ChangeNotifier {
  static const sleepAfter = Duration(seconds: 20);
  LockScreenState _state = LockScreenState.locked;
  Timer? _idle;

  LockScreenState get state => _state;

  void focusEmail() => _move({LockScreenState.locked}, LockScreenState.email);

  void focusPassword() => _move({
    LockScreenState.locked,
    LockScreenState.email,
  }, LockScreenState.password);

  void togglePeek() {
    _move({LockScreenState.password}, LockScreenState.peek) ||
        _move({LockScreenState.peek}, LockScreenState.password);
  }

  void submit() => _move({
    LockScreenState.password,
    LockScreenState.peek,
  }, LockScreenState.checking);

  void fail() => _move({LockScreenState.checking}, LockScreenState.error);

  void succeed() => _move({
    LockScreenState.checking,
    LockScreenState.hello,
  }, LockScreenState.success);

  /// Any keystroke or pointer input: clears an error, wakes from sleep.
  void input() {
    _move({LockScreenState.error}, LockScreenState.password) ||
        _move({LockScreenState.asleep}, LockScreenState.locked);
  }

  void helloStarted() => _move({LockScreenState.locked}, LockScreenState.hello);

  void helloCancelled() =>
      _move({LockScreenState.hello}, LockScreenState.locked);

  void reset([LockScreenState state = LockScreenState.locked]) =>
      _move(LockScreenState.values.toSet(), state);

  void startIdleWatch() {
    _idle?.cancel();
    _idle = Timer(sleepAfter, () {
      if (_state == LockScreenState.locked) _set(LockScreenState.asleep);
    });
  }

  void stopIdleWatch() {
    _idle?.cancel();
    _idle = null;
  }

  /// Every call restarts a running idle watch, legal or not: it is user activity.
  bool _move(Set<LockScreenState> from, LockScreenState to) {
    if (_idle != null) startIdleWatch();
    if (!from.contains(_state)) return false;
    _set(to);
    return true;
  }

  void _set(LockScreenState to) {
    if (_state == to) return;
    _state = to;
    notifyListeners();
  }

  @override
  void dispose() {
    stopIdleWatch();
    super.dispose();
  }
}
