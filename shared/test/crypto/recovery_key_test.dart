// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/hex.dart';

void main() {
  final key = List.generate(32, (i) => i);
  const text =
      'AAAQ-EAYE-AUDA-OCAJ-BIFQ-YDIO-B4IB-CEQT-CQKR-MFYY-DENB-WHA5-DYPW-G';

  test('encodes the known answer: 53 base32 chars in groups of 4', () {
    expect(RecoveryKey.encode(key), text);
    expect(text.replaceAll('-', '').length, 53);
  });

  test('decode normalises case, spaces and dashes', () {
    expect(RecoveryKey.decode(text), key);
    expect(RecoveryKey.decode(text.toLowerCase().replaceAll('-', ' ')), key);
    expect(RecoveryKey.decode(text.replaceAll('-', '')), key);
  });

  test('a changed character or trailing bit is refused', () {
    for (final bad in [
      'B${text.substring(1)}',
      '${text.substring(0, text.length - 1)}H',
    ]) {
      expect(
        () => RecoveryKey.decode(bad),
        throwsA(isA<InvalidRecoveryKey>()),
        reason: bad,
      );
    }
  });

  test('wrong length or alphabet is refused', () {
    for (final bad in [
      text.substring(0, text.length - 2),
      '${text}A',
      text.replaceFirst('A', '1'),
      text.replaceFirst('A', '!'),
      '',
    ]) {
      expect(
        () => RecoveryKey.decode(bad),
        throwsA(isA<InvalidRecoveryKey>()),
        reason: bad,
      );
    }
    expect(() => RecoveryKey.encode(List.filled(31, 0)), throwsArgumentError);
  });

  test('generate gives 32 fresh random bytes', () {
    final a = RecoveryKey.generate(), b = RecoveryKey.generate();
    expect(a.length, 32);
    expect(a, isNot(b));
    expect(RecoveryKey.decode(RecoveryKey.encode(a)), a);
  });

  test('auth and wrap keys are separate HKDF outputs (known answer)', () async {
    expect(
      hex(await recoveryAuthKey(key)),
      '6e7bfe7b86ec20a19f1316e1802d64e76f275a22595ab84e86b2ac8bb0ff8d82',
    );
    expect(
      hex(await recoveryWrapKey(key)),
      '2c4369445d66b371cc9f9f0dfdebf28db03c8a61be556df0197a8fe2a4348e3e',
    );
  });
}
