// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/foundation.dart';

/// Locks after [timeout] without activity (zero: never) and reports idleness after [idleAfter].
class AutoLock {
  AutoLock({required this.timeout, required this.onLock, this.onIdle});

  /// Read at every restart, so a settings change applies from the next activity.
  final Duration Function() timeout;
  final VoidCallback onLock;
  final VoidCallback? onIdle;
  static const idleAfter = Duration(minutes: 5);
  Timer? _lock;
  Timer? _idle;
  bool _running = false;

  void start() {
    _running = true;
    _arm();
  }

  void stop() {
    _running = false;
    _lock?.cancel();
    _idle?.cancel();
  }

  void recordActivity() {
    if (_running) _arm();
  }

  void _arm() {
    _lock?.cancel();
    _idle?.cancel();
    final lockAfter = timeout();
    if (lockAfter > Duration.zero) {
      _lock = Timer(lockAfter, () {
        stop();
        onLock();
      });
    }
    if (onIdle case final idle?) _idle = Timer(idleAfter, idle);
  }
}
