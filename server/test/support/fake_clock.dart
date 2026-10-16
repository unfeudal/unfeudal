// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:unfeudal_server/src/util/clock.dart';

class FakeClock implements Clock {
  FakeClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration d) => _now = _now.add(d);
}
