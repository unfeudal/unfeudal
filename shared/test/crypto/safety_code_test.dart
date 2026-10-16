// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  final zeros = List.filled(32, 0), seq = List.generate(32, (i) => i);

  test('safety code vectors', () {
    expect(safetyCode(zeros), '34584 15407 68110 72389 41680 02623');
    expect(safetyCode(seq), '11590 49842 13307 78876 30539 70167');
  });

  test('fingerprint is the first 20 bytes of SHA-256 in lowercase hex', () {
    expect(keyFingerprint(zeros), '66687aadf862bd776c8fc18b8e9f8e2008971485');
    expect(keyFingerprint(seq), '630dcd2966c4336691125448bbb25b4ff412a49c');
  });

  test('keys must be 32 bytes', () {
    expect(() => safetyCode(List.filled(31, 0)), throwsArgumentError);
    expect(() => keyFingerprint(List.filled(33, 0)), throwsArgumentError);
  });
}
