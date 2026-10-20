// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:unfeudal_server/src/api/errors.dart';
import 'package:unfeudal_server/src/auth/secret_hash.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  test('verifySecret matches the pinned Argon2id vector', () async {
    const vector =
        '16253e23a29b20d7c7a0c05f9150e74baaa6cf1832edc838d484fc250a02bef9';
    final hash = [
      for (var i = 0; i < vector.length; i += 2)
        int.parse(vector.substring(i, i + 2), radix: 16),
    ];
    final stored =
        'argon2id\$1024\$1\$1\$${b64(utf8.encode('somesaltsomesalt'))}\$${b64(hash)}';
    expect(await verifySecret(stored, utf8.encode('password')), isTrue);
    expect(await verifySecret(stored, utf8.encode('passwore')), isFalse);
  });

  test(
    'hashSecret writes the stored format with a fresh salt and verifies',
    () async {
      final key = List.filled(32, 7);
      final a = await hashSecret(key, SecretHashParams.testing);
      final b = await hashSecret(key, SecretHashParams.testing);
      expect(
        a,
        matches(
          RegExp(
            r'^argon2id\$1024\$1\$1\$[A-Za-z0-9_-]{22}\$[A-Za-z0-9_-]{43}$',
          ),
        ),
      );
      expect(a, isNot(b));
      expect(
        (await verifySecret(a, key), await verifySecret(a, List.filled(32, 8))),
        (true, false),
      );
      expect(
        (
          SecretHashParams.server.m,
          SecretHashParams.server.t,
          SecretHashParams.server.p,
        ),
        (19456, 2, 1),
      );
    },
  );

  test('a malformed or oversized stored hash never verifies', () async {
    for (final s in [
      '',
      'bcrypt\$x',
      'argon2id\$1024\$1\$1\$AAAA',
      'argon2id\$999999\$1\$1\$AAAAAAAAAAAAAAAAAAAAAA\$AAAA',
      'argon2id\$x\$1\$1\$AAAAAAAAAAAAAAAAAAAAAA\$AAAA',
    ]) {
      expect(await verifySecret(s, [1]), isFalse, reason: s);
    }
  });

  test('dummyHash is one stable hash per params', () async {
    expect(
      await dummyHash(SecretHashParams.testing),
      await dummyHash(SecretHashParams.testing),
    );
    expect(
      await verifySecret(
        await dummyHash(SecretHashParams.testing),
        List.filled(32, 0),
      ),
      isFalse,
    );
  });

  test('Argon2Gate: at most slots run, 4 × slots wait, the next is 429 retry-after 1', () async {
    final gate = Argon2Gate(1);
    final release = Completer<void>();
    var running = 0, peak = 0;
    Future<void> work() async {
      running++;
      peak = max(peak, running);
      await release.future;
      running--;
    }

    final admitted = [for (var i = 0; i < 5; i++) gate.run(work)];
    try {
      await gate.run(work);
      fail('not refused');
    } on ApiError catch (e) {
      expect((e.code, e.retryAfter), (ApiErrorCode.rateLimited, 1));
    }
    release.complete();
    await Future.wait(admitted);
    expect(peak, 1);
    await gate.run(work);
  });

  test('Argon2Gate.admit: a full gate refuses before the check runs', () async {
    final gate = Argon2Gate(1);
    final release = Completer<void>();
    final queued = [for (var i = 0; i < 5; i++) gate.run(() => release.future)];
    var ran = false;
    await expectLater(
      gate.admit(HashPriority.other, () async => ran = true),
      throwsA(
        isA<ApiError>().having((e) => e.code, 'code', ApiErrorCode.rateLimited),
      ),
    );
    expect(ran, isFalse);
    release.complete();
    await Future.wait(queued);
  });

  test('an admitted check keeps its place: the queue filling meanwhile never refuses its hash', () async {
    final gate = Argon2Gate(1);
    final go = Completer<void>(), release = Completer<void>();
    final check = gate.admit(HashPriority.other, () async {
      await go.future;
      return gate.run(() async => 'hashed');
    });
    final others = [for (var i = 0; i < 4; i++) gate.run(() => release.future)];
    await expectLater(gate.run(() async {}), throwsA(isA<ApiError>()));
    go.complete();
    await pumpEventQueue();
    release.complete();
    expect(await check, 'hashed');
    await Future.wait(others);
  });

  test('a check that fails before its hash gives its place back', () async {
    final gate = Argon2Gate(1);
    final release = Completer<void>();
    final queued = [for (var i = 0; i < 4; i++) gate.run(() => release.future)];
    await expectLater(
      gate.admit(HashPriority.other, () async => throw StateError('429')),
      throwsStateError,
    );
    final last = gate.run(() => release.future);
    release.complete();
    await Future.wait([...queued, last]);
  });

  test('a waiting sign-in goes before the other waiting hashes', () async {
    final gate = Argon2Gate(1);
    final release = Completer<void>();
    final order = <String>[];
    final first = gate.run(() => release.future);
    final other = gate.run(() async => order.add('other'));
    final signIn = gate.admit(
      HashPriority.signIn,
      () => gate.run(() async => order.add('sign-in')),
    );
    await pumpEventQueue();
    release.complete();
    await Future.wait([first, other, signIn]);
    expect(order, ['sign-in', 'other']);
  });
}
