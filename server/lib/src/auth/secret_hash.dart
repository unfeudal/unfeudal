// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/errors.dart';

class SecretHashParams {
  const SecretHashParams(this.memoryKib, this.iterations, this.parallelism);

  final int memoryKib;
  final int iterations;
  final int parallelism;

  static const server = SecretHashParams(19456, 2, 1);

  /// Tests only.
  static const testing = SecretHashParams(1024, 1, 1);
}

/// Which waiting hash goes first: a sign-in never waits behind password changes, setups and invites.
enum HashPriority { signIn, other }

/// Bounds memory and CPU before authentication: [slots] hashes at once, 4 times [slots] waiting, the next gets
/// 429. A credential check is admitted once, before the attempt is counted, and keeps its place until it
/// ends: the queue filling meanwhile never refuses its hashes.
class Argon2Gate {
  Argon2Gate(this.slots);

  final int slots;
  int _running = 0;
  final _waiting = {
    for (final priority in HashPriority.values)
      priority: Queue<Completer<void>>(),
  };
  // Admitted checks between their hashes: their places stay counted.
  int _held = 0;
  static final _admission = Object();

  int get _queued => _waiting.values.fold(0, (sum, q) => sum + q.length);

  void _refuseIfFull() {
    if (_running >= slots && _queued + _held >= 4 * slots) {
      throw ApiError(
        ApiErrorCode.rateLimited,
        'Server busy. Try again.',
        retryAfter: 1,
      );
    }
  }

  /// Runs [check] with a place kept for its hashes, or throws the busy 429 before it starts.
  Future<T> admit<T>(HashPriority priority, Future<T> Function() check) async {
    _refuseIfFull();
    _held++;
    try {
      return await runZoned(check, zoneValues: {_admission: priority});
    } finally {
      _held--;
    }
  }

  Future<T> run<T>(Future<T> Function() work) async {
    final admitted = Zone.current[_admission] as HashPriority?;
    // An admitted check's place moves from held to running or waiting, and back after.
    if (admitted != null) _held--;
    try {
      if (_running < slots) {
        _running++;
      } else {
        if (admitted == null) _refuseIfFull();
        final turn = Completer<void>();
        _waiting[admitted ?? HashPriority.other]!.add(turn);
        // The finishing hash hands its slot over.
        await turn.future;
      }
      try {
        return await work();
      } finally {
        _handOver();
      }
    } finally {
      if (admitted != null) _held++;
    }
  }

  void _handOver() {
    for (final priority in HashPriority.values) {
      if (_waiting[priority]!.isNotEmpty) {
        _waiting[priority]!.removeFirst().complete();
        return;
      }
    }
    _running--;
  }
}

final _gate = Argon2Gate(Platform.numberOfProcessors);

/// Runs a credential check admitted by the process-wide gate; a full gate is a 429 that counts nothing.
Future<T> admitCredentialCheck<T>(
  HashPriority priority,
  Future<T> Function() check,
) => _gate.admit(priority, check);

// Argon2id runs in another isolate: the pure-Dart hash would otherwise block every request.
Future<Uint8List> _argon2id(
  List<int> secret,
  List<int> salt,
  SecretHashParams params,
) => _gate.run(
  () => Isolate.run(() async {
    final key = await Argon2id(
      memory: params.memoryKib,
      iterations: params.iterations,
      parallelism: params.parallelism,
      hashLength: 32,
    ).deriveKey(secretKey: SecretKey(secret), nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  }),
);

/// Stored as `argon2id$m$t$p$<b64 salt>$<b64 hash>`.
Future<String> hashSecret(List<int> secret, SecretHashParams params) async {
  final salt = secureBytes(16);
  final hash = await _argon2id(secret, salt, params);
  return 'argon2id\$${params.memoryKib}\$${params.iterations}\$${params.parallelism}\$${b64(salt)}\$${b64(hash)}';
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
  return constantTimeEquals(
    await _argon2id(secret, salt, SecretHashParams(m, t, p)),
    expected,
  );
}

final _dummies = <SecretHashParams, Future<String>>{};

/// Hash checked when the email is unknown, so every login costs one Argon2id.
Future<String> dummyHash(SecretHashParams params) =>
    _dummies.putIfAbsent(params, () => hashSecret(secureBytes(32), params));
