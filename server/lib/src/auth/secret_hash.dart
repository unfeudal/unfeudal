// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart' show constantTimeBytesEquality;
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/errors.dart';

class SecretHashParams {
  const SecretHashParams(this.m, this.t, this.p);

  final int m; // KiB
  final int t;
  final int p;

  static const server = SecretHashParams(19456, 2, 1);

  /// Tests only.
  static const testing = SecretHashParams(1024, 1, 1);
}

/// Bounds memory and CPU before authentication: [slots] hashes at once, 4 × [slots] waiting, the next → 429.
class Argon2Gate {
  Argon2Gate(this.slots);

  final int slots;
  int _running = 0;
  final _waiting = Queue<Completer<void>>();

  /// The 429 [run] would throw now; lets a caller refuse before it counts the attempt.
  void refuseIfFull() {
    if (_running >= slots && _waiting.length >= 4 * slots) {
      throw ApiError(
        ApiErrorCode.rateLimited,
        'Server busy. Try again.',
        retryAfter: 1,
      );
    }
  }

  Future<T> run<T>(Future<T> Function() work) async {
    if (_running < slots) {
      _running++;
    } else {
      refuseIfFull();
      final turn = Completer<void>();
      _waiting.add(turn);
      // The finishing hash hands its slot over.
      await turn.future;
    }
    try {
      return await work();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }
}

// ponytail: one process-wide gate sized by cores; split it per route if sign-ins starve behind other hashes.
final _gate = Argon2Gate(Platform.numberOfProcessors);

/// A full Argon2 queue is a 429 that counts nothing: credential checks call this before the rate limiter.
void refuseIfArgon2Busy() => _gate.refuseIfFull();

/// Argon2id in another isolate: the pure-Dart hash would otherwise block every request.
Future<Uint8List> _argon2id(
  List<int> secret,
  List<int> salt,
  int m,
  int t,
  int p,
) => _gate.run(
  () => Isolate.run(() async {
    final key = await Argon2id(
      memory: m,
      iterations: t,
      parallelism: p,
      hashLength: 32,
    ).deriveKey(secretKey: SecretKey(secret), nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  }),
);

/// Stored as `argon2id$m$t$p$<b64 salt>$<b64 hash>`.
Future<String> hashSecret(List<int> secret, SecretHashParams params) async {
  final salt = secureBytes(16);
  final hash = await _argon2id(secret, salt, params.m, params.t, params.p);
  return 'argon2id\$${params.m}\$${params.t}\$${params.p}\$${b64(salt)}\$${b64(hash)}';
}

/// False for a wrong secret and for any malformed or out-of-bounds stored hash.
Future<bool> verifySecret(String stored, List<int> secret) async {
  final parts = stored.split('\$');
  if (parts.length != 6 || parts[0] != 'argon2id') return false;
  final (m, t, p) = (
    int.tryParse(parts[1]),
    int.tryParse(parts[2]),
    int.tryParse(parts[3]),
  );
  if (m == null ||
      t == null ||
      p == null ||
      m < 8 ||
      m > 262144 ||
      t < 1 ||
      t > 8 ||
      p < 1 ||
      p > 16) {
    return false;
  }
  final Uint8List salt, expected;
  try {
    salt = unb64(parts[4]);
    expected = unb64(parts[5]);
  } on FormatException {
    return false;
  }
  if (salt.length < 8 || expected.length != 32) return false;
  return constantTimeBytesEquality.equals(
    await _argon2id(secret, salt, m, t, p),
    expected,
  );
}

final _dummies = <SecretHashParams, Future<String>>{};

/// Hash checked when the email is unknown, so every login costs one Argon2id.
Future<String> dummyHash(SecretHashParams params) =>
    _dummies.putIfAbsent(params, () => hashSecret(secureBytes(32), params));
