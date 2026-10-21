// SPDX-License-Identifier: Apache-2.0

/// The `event` of a POST /events/ssh report.
enum SshEvent {
  open('open'),
  close('close'),
  forwardStart('forward_start'),
  forwardStop('forward_stop');

  const SshEvent(this.wire);

  final String wire;

  /// Null for a value this version does not know.
  static SshEvent? fromWire(Object? wire) =>
      values.where((e) => e.wire == wire).firstOrNull;
}
