// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  test('every event has its wire name', () {
    expect(SshEvent.values.map((e) => e.wire), [
      'open',
      'close',
      'forward_start',
      'forward_stop',
    ]);
  });

  test('fromWire reads a known name and refuses anything else', () {
    expect(SshEvent.fromWire('forward_start'), SshEvent.forwardStart);
    expect(SshEvent.fromWire('opened'), isNull);
    expect(SshEvent.fromWire(1), isNull);
  });
}
