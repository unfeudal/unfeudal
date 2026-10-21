// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/session/biometrics.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';

void main() {
  late FakeSecureKv kv;
  late FakeBiometricBackend hw;
  late BiometricUnlock bio;
  final userKey = SymmetricCipher.newKey();
  setUp(() {
    kv = FakeSecureKv();
    hw = FakeBiometricBackend();
    bio = BiometricUnlock(kv, hw);
  });

  test('enable then unlock gives the userKey back', () async {
    expect(await bio.enable(userKey, reason: 'r'), isTrue);
    expect(await bio.isEnabled(), isTrue);
    expect(await bio.unlock(reason: 'r'), userKey);
  });

  test('the stored wrap never contains the raw userKey; keyId biometric, aad biometric/userKey', () async {
    await bio.enable(userKey, reason: 'r');
    final raw = kv.values[BiometricUnlock.storageKey]!;
    expect(raw, isNot(contains(b64(userKey))));
    final e = Envelope.fromJson(jsonDecode(raw));
    expect(e.keyId, 'biometric');
    expect(
      await SymmetricCipher.decrypt(
        hw.secretBytes!,
        e,
        aad: utf8.encode('biometric/userKey'),
      ),
      userKey,
    );
  });

  test(
    'a cancelled prompt keeps it; a changed hardware secret wipes it',
    () async {
      await bio.enable(userKey, reason: 'r');
      hw.cancel = true;
      expect(
        (await bio.unlock(reason: 'r'), await bio.isEnabled()),
        (null, true),
      );
      // A new fingerprint enrolled: the old secret is gone.
      hw
        ..cancel = false
        ..secretBytes = SymmetricCipher.newKey();
      expect(await bio.unlock(reason: 'r'), isNull);
      expect((await bio.isEnabled(), hw.deleted), (false, 1));
    },
  );

  test('without hardware enable refuses', () async {
    expect(
      await BiometricUnlock(
        FakeSecureKv(),
        FakeBiometricBackend(hasHardware: false),
      ).enable(userKey, reason: 'r'),
      isFalse,
    );
  });

  test('disable wipes the keystore entry and the hardware secret', () async {
    await bio.enable(userKey, reason: 'r');
    await bio.disable();
    expect(
      (
        kv.values.containsKey(BiometricUnlock.storageKey),
        hw.secretBytes,
        hw.deleted,
      ),
      (false, null, 1),
    );
  });
}
