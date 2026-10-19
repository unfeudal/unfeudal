// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  final crypto = AccountCrypto(kdf: KdfParams.testing, allowTestingKdf: true);
  late NewAccount alice;
  late NewAccount bob;
  setUpAll(() async {
    alice = await crypto.create('alice password');
    bob = await crypto.create('bob password');
  });

  PayloadAad aad(
    String id, {
    String type = 'host',
    PayloadPart part = PayloadPart.meta,
  }) => PayloadAad(
    itemId: id,
    part: part,
    type: type,
    scope: ItemScope.personal,
    orgId: null,
    folderId: null,
  );

  test(
    'payloads moved to another item, or a secret served as meta, never open',
    () async {
      final key = alice.unlocked.userKey;
      final a = newId(), b = newId();
      final meta = await PayloadCrypto.seal(
        aad(a),
        {'name': 'a'},
        key,
        KeyIds.user,
        seq: 1,
      );
      final secret = await PayloadCrypto.seal(
        aad(a, type: 'identity', part: PayloadPart.secret),
        {'password': 'x'},
        key,
        KeyIds.user,
        seq: 1,
      );
      await expectLater(
        PayloadCrypto.open(aad(b), meta, key),
        throwsA(isA<DecryptionFailed>()),
      );
      await expectLater(
        PayloadCrypto.open(aad(a, type: 'identity'), secret, key),
        throwsA(isA<DecryptionFailed>()),
      );
    },
  );

  test('a bundle stitched from two accounts never unlocks, by password, recovery key or userKey', () async {
    final a = alice.bundle.toJson(), b = bob.bundle.toJson();
    for (final raw in [
      {...a, 'wrappedPrivateKey': b['wrappedPrivateKey']},
      {...a, 'publicKey': b['publicKey']},
    ]) {
      final stitched = AccountBundle.fromJson(raw);
      await expectLater(
        crypto.unlock(stitched, 'alice password'),
        throwsA(isA<WrongPassword>()),
      );
      await expectLater(
        crypto.unlockWithUserKey(stitched, alice.unlocked.userKey),
        throwsA(isA<WrongPassword>()),
      );
    }
    final bobsWrap = AccountBundle.fromJson({
      ...a,
      'wrappedUserKey': b['wrappedUserKey'],
      'salt': b['salt'],
    });
    await expectLater(
      crypto.unlock(bobsWrap, 'bob password'),
      throwsA(isA<WrongPassword>()),
    );
    final bobsRecovery = AccountBundle.fromJson({
      ...a,
      'wrappedUserKeyByRecovery': b['wrappedUserKeyByRecovery'],
    });
    await expectLater(
      crypto.unlockWithRecovery(bobsRecovery, bob.recoveryKey),
      throwsA(isA<InvalidRecoveryKey>()),
    );
  });

  test(
    'a memory-bomb, weak or unknown KDF is refused before any derivation',
    () async {
      final production = AccountCrypto(kdf: KdfParams.defaults);
      for (final (kdf, error) in [
        (
          {'alg': 'argon2id', 'm': 262144 * 4, 't': 3, 'p': 4},
          isA<FormatException>(),
        ),
        ({'alg': 'argon2id', 'm': 1024, 't': 1, 'p': 1}, isA<WeakKdf>()),
        ({'alg': 'scrypt', 'm': 65536, 't': 3, 'p': 4}, isA<UnsupportedKdf>()),
      ]) {
        final sw = Stopwatch()..start();
        await expectLater(
          () async => production.unlock(
            AccountBundle.fromJson({...alice.bundle.toJson(), 'kdf': kdf}),
            'alice password',
          ),
          throwsA(error),
          reason: '$kdf',
        );
        expect(
          sw.elapsed,
          lessThan(const Duration(milliseconds: 500)),
          reason: '$kdf',
        );
      }
    },
  );

  test(
    'a downgraded or future envelope is refused when used, never decrypted',
    () async {
      final e = (await SymmetricCipher.encrypt(alice.unlocked.userKey, [
        1,
        2,
        3,
      ], KeyIds.user)).toJson();
      for (final changed in [
        {...e, 'v': 2},
        {...e, 'alg': 'aes-128-ecb'},
      ]) {
        await expectLater(
          SymmetricCipher.decrypt(
            alice.unlocked.userKey,
            Envelope.fromJson(changed),
          ),
          throwsA(isA<UnsupportedEnvelope>()),
        );
      }
    },
  );

  test('a tampered export never opens and cannot lower its KDF', () async {
    final text = await VaultExport.seal(
      const [],
      'twelve chars!',
      kdf: KdfParams.testing,
    );
    final j = jsonDecode(text) as Map<String, Object?>;
    final data = Map<String, Object?>.of(j['data']! as Map<String, Object?>);
    final ct = unb64(data['ct']! as String)..[0] ^= 1;
    final flipped = jsonEncode({
      ...j,
      'data': {...data, 'ct': b64(ct)},
    });
    await expectLater(
      VaultExport.open(flipped, 'twelve chars!', allowTestingKdf: true),
      throwsA(isA<WrongPassword>()),
    );
    await expectLater(
      VaultExport.open(text, 'twelve chars!'),
      throwsA(isA<WeakKdf>()),
    );
  });
}
