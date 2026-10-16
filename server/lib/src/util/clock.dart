// SPDX-License-Identifier: AGPL-3.0-or-later

/// Injected so tests control time.
abstract class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
