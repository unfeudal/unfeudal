// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/hex.dart';

void main() {
  final salt = utf8.encode('somesaltsomesalt');
  const t1 = KdfParams.testing;
  const t2p4 = KdfParams(alg: 'argon2id', m: 1024, t: 2, p: 4);

  test('Argon2id matches the reference vectors (1 and 4 lanes)', () async {
    expect(
      hex(await argon2id('password', salt, t1)),
      '16253e23a29b20d7c7a0c05f9150e74baaa6cf1832edc838d484fc250a02bef9',
    );
    expect(
      hex(await argon2id('password', salt, t2p4)),
      '41d149ca71825f08e61ec006d2aada40c2fbb4003e9578363a64f6b3282590ad',
    );
  });

  test('HKDF-SHA256: RFC 5869 case 1 (library) and case 3 (hkdf32)', () async {
    final okm = await Hkdf(hmac: Hmac.sha256(), outputLength: 42).deriveKey(
      secretKey: SecretKey(List.filled(22, 0x0b)),
      nonce: unhex('000102030405060708090a0b0c'),
      info: unhex('f0f1f2f3f4f5f6f7f8f9'),
    );
    expect(
      hex(await okm.extractBytes()),
      '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865',
    );
    // hkdf32 takes info as text; case 3 has empty info.
    expect(
      hex(await hkdf32(List.filled(22, 0x0b), '')),
      '8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d',
    );
  });

  test('deriveMasterKeys splits auth and enc keys (known answer)', () async {
    final k = await deriveMasterKeys('password', salt, t1);
    expect(
      hex(k.authKey),
      '9ca1e4e89dca2f0969a05e2b0062e88f0b2a922ad03084731e71cc61d79af3ec',
    );
    expect(
      hex(k.encKey),
      'a6a1359a3dbc285e7abce7f4ca717a6c2228b81ced039edfc1027c9d4c438f96',
    );
  });

  test('NFD and NFC passwords derive the same keys', () async {
    const nfc = 'café-secret', nfd = 'café-secret';
    expect(passwordLength(nfd), passwordLength(nfc));
    expect(
      (await deriveMasterKeys(nfd, salt, t1)).encKey,
      (await deriveMasterKeys(nfc, salt, t1)).encKey,
    );
  });

  test('KdfParams JSON keeps unknown fields and parses an unknown alg', () {
    final json = {'future': 1, 'alg': 'argon2id', 'm': 65536, 't': 3, 'p': 4};
    expect(jsonEncode(KdfParams.fromJson(json).toJson()), jsonEncode(json));
    expect(
      KdfParams.fromJson({'alg': 'scrypt', 'm': 1, 't': 1, 'p': 1}).alg,
      'scrypt',
    );
    for (final bad in [
      'x',
      {'alg': 'argon2id', 'm': '1024', 't': 1, 'p': 1},
      {'alg': 'argon2id', 'm': 1024, 't': 1},
      {'alg': 'argon2id', 'm': 0, 't': 1, 'p': 1},
      {'m': 1024, 't': 1, 'p': 1},
    ]) {
      expect(
        () => KdfParams.fromJson(bad),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  test('defaults, ceiling and testing presets have the pinned values', () {
    KdfParams.defaults.ensureAcceptable();
    KdfParams.ceiling.ensureAcceptable();
    expect(
      (KdfParams.defaults.m, KdfParams.defaults.t, KdfParams.defaults.p),
      (65536, 3, 4),
    );
    expect(
      (KdfParams.ceiling.m, KdfParams.ceiling.t, KdfParams.ceiling.p),
      (262144, 8, 16),
    );
    expect(
      (KdfParams.testing.m, KdfParams.testing.t, KdfParams.testing.p),
      (1024, 1, 1),
    );
  });

  test('ensureAcceptable refuses params below the floor with WeakKdf', () {
    expect(() => KdfParams.testing.ensureAcceptable(), throwsA(isA<WeakKdf>()));
    KdfParams.testing.ensureAcceptable(floor: KdfParams.testing);
    expect(
      () => const KdfParams(
        alg: 'argon2id',
        m: 65536,
        t: 2,
        p: 4,
      ).ensureAcceptable(),
      throwsA(isA<WeakKdf>()),
    );
    expect(
      () => const KdfParams(
        alg: 'argon2id',
        m: 512,
        t: 1,
        p: 1,
      ).ensureAcceptable(floor: KdfParams.testing),
      throwsA(isA<WeakKdf>()),
    );
  });

  test('ensureAcceptable refuses params above the ceiling as malformed', () {
    expect(
      () => const KdfParams(
        alg: 'argon2id',
        m: 262145,
        t: 3,
        p: 4,
      ).ensureAcceptable(),
      throwsFormatException,
    );
    expect(
      () => const KdfParams(
        alg: 'argon2id',
        m: 65536,
        t: 9,
        p: 4,
      ).ensureAcceptable(),
      throwsFormatException,
    );
    expect(
      () => const KdfParams(
        alg: 'argon2id',
        m: 65536,
        t: 3,
        p: 17,
      ).ensureAcceptable(floor: KdfParams.testing),
      throwsFormatException,
    );
  });

  test('ensureAcceptable refuses an unknown alg with UnsupportedKdf', () {
    expect(
      () => const KdfParams(alg: 'scrypt', m: 1, t: 1, p: 1).ensureAcceptable(),
      throwsA(isA<UnsupportedKdf>()),
    );
  });

  test(
    'derivation refuses a bad salt or out-of-range params before any work',
    () async {
      await expectLater(
        deriveMasterKeys('password', salt.sublist(1), t1),
        throwsFormatException,
      );
      await expectLater(
        argon2id(
          'password',
          salt,
          const KdfParams(alg: 'argon2id', m: 1 << 30, t: 1, p: 1),
        ),
        throwsFormatException,
      );
      await expectLater(
        argon2id(
          'password',
          salt,
          const KdfParams(alg: 'x', m: 1024, t: 1, p: 1),
        ),
        throwsA(isA<UnsupportedKdf>()),
      );
    },
  );
}
