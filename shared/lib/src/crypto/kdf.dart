// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../util/json_reader.dart';
import 'errors.dart';

class KdfParams {
  const KdfParams({
    required this.alg,
    required this.m,
    required this.t,
    required this.p,
    this.extra = const {},
  });

  factory KdfParams.fromJson(Object? json) {
    final r = JsonReader(json, 'kdf');
    return KdfParams(
      alg: r.text('alg', max: 64),
      m: r.integer('m', min: 1),
      t: r.integer('t', min: 1),
      p: r.integer('p', min: 1),
      extra: r.extra(const {'alg', 'm', 't', 'p'}),
    );
  }

  final String alg;
  final int m; // KiB
  final int t;
  final int p;
  final Map<String, Object?> extra;

  /// Also the floor.
  static const defaults = KdfParams(alg: 'argon2id', m: 65536, t: 3, p: 4);
  static const ceiling = KdfParams(alg: 'argon2id', m: 262144, t: 8, p: 16);
  static const testing = KdfParams(alg: 'argon2id', m: 1024, t: 1, p: 1);

  /// UnsupportedKdf for another alg, FormatException above the ceiling, WeakKdf below [floor]
  /// (only tests pass a floor under [defaults]).
  void ensureAcceptable({KdfParams floor = defaults}) {
    if (alg != 'argon2id') throw UnsupportedKdf(alg);
    if (m > ceiling.m || t > ceiling.t || p > ceiling.p) {
      throw const FormatException('kdf above the ceiling');
    }
    if (m < floor.m || t < floor.t || p < floor.p) throw const WeakKdf();
  }

  Map<String, Object?> toJson() => {
    ...extra,
    'alg': alg,
    'm': m,
    't': t,
    'p': p,
  };
}

/// Length in code points as the minimum-length rules count it: after NFC normalization.
int passwordLength(String password) => unorm.nfc(password).runes.length;

/// Raw Argon2id v1.3 of NFC(password). Always enforces alg, ceiling and the testing floor;
/// callers holding params from outside also call `ensureAcceptable()` with their own floor.
Future<Uint8List> argon2id(
  String password,
  List<int> salt,
  KdfParams kdf,
) async {
  kdf.ensureAcceptable(floor: KdfParams.testing);
  if (salt.length != 16) throw const FormatException('salt must be 16 bytes');
  final secret = utf8.encode(unorm.nfc(password));
  // seconds of CPU and up to the memory ceiling: off the caller's isolate, so a UI thread keeps painting
  return Isolate.run(() async {
    final key = await Argon2id(
      memory: kdf.m,
      iterations: kdf.t,
      parallelism: kdf.p,
      hashLength: 32,
    ).deriveKey(secretKey: SecretKey(secret), nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  });
}

Future<Uint8List> hkdf32(List<int> ikm, String info) async {
  final key = await Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  ).deriveKey(secretKey: SecretKey(ikm), info: utf8.encode(info));
  return Uint8List.fromList(await key.extractBytes());
}

/// `authKey` is sent as the login proof; `encKey` never leaves the device.
Future<({Uint8List authKey, Uint8List encKey})> deriveMasterKeys(
  String password,
  List<int> salt,
  KdfParams kdf,
) async {
  final argon = await argon2id(password, salt, kdf);
  return (
    authKey: await hkdf32(argon, 'unfeudal/auth/v1'),
    encKey: await hkdf32(argon, 'unfeudal/enc/v1'),
  );
}
