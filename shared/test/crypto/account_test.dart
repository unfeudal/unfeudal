// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  final crypto = AccountCrypto(kdf: KdfParams.testing, allowTestingKdf: true);
  late NewAccount acc;
  setUpAll(() async => acc = await crypto.create('correct horse'));

  Map<String, Object?> without(AccountBundle b, List<String> keys) =>
      b.toJson()..removeWhere((k, _) => keys.contains(k));

  test('create then unlock gives the same userKey and key pair', () async {
    final bundle = AccountBundle.fromJson(
      jsonDecode(jsonEncode(acc.bundle.toJson())),
    );
    final u = await crypto.unlock(bundle, 'correct horse');
    expect(u.userKey, acc.unlocked.userKey);
    expect((await u.keyPair.extractPublicKey()).bytes, bundle.publicKey);
    expect(u.bundle, same(bundle));
  });

  test('bundle uses the contract keyIds and holds no clear key', () async {
    final b = acc.bundle;
    expect(
      [
        b.wrappedUserKey.keyId,
        b.wrappedUserKeyByRecovery.keyId,
        b.wrappedPrivateKey.keyId,
      ],
      ['master', 'recovery', 'user-x25519'],
    );
    expect((b.salt.length, b.publicKey.length), (16, 32));
    final dump = jsonEncode(b.toJson());
    expect(dump.contains(b64(acc.unlocked.userKey)), isFalse);
    expect(
      dump.contains(b64(await acc.unlocked.keyPair.extractPrivateKeyBytes())),
      isFalse,
    );
  });

  test('authKey equals deriveMasterKeys of the NFC password', () async {
    final a = await crypto.create('café-horse');
    final m = await deriveMasterKeys(
      'café-horse',
      a.bundle.salt,
      a.bundle.kdf,
    );
    expect(m.authKey, a.authKey);
    expect(
      (await crypto.unlock(a.bundle, 'café-horse')).userKey,
      a.unlocked.userKey,
    );
  });

  test('wrong password throws WrongPassword', () async {
    await expectLater(
      crypto.unlock(acc.bundle, 'wrong horse'),
      throwsA(isA<WrongPassword>()),
    );
  });

  test('passwords under 8 code points after NFC are refused', () async {
    await expectLater(crypto.create('short12'), throwsA(isA<WeakPassword>()));
    await expectLater(
      crypto.create('cafééab'),
      throwsA(isA<WeakPassword>()),
    ); // 9 units, 7 after NFC
  });

  test('recovery key unlocks the same userKey; its auth key matches', () async {
    final r = await crypto.unlockWithRecovery(
      acc.bundle,
      acc.recoveryKey.toLowerCase(),
    );
    expect(r.userKey, acc.unlocked.userKey);
    expect(
      await recoveryAuthKey(RecoveryKey.decode(acc.recoveryKey)),
      acc.recoveryAuthKey,
    );
    expect(acc.recoveryAuthKey, isNot(acc.authKey));
  });

  test(
    'another account recovery key or garbage throws InvalidRecoveryKey',
    () async {
      final other = await crypto.create('battery staple');
      await expectLater(
        crypto.unlockWithRecovery(acc.bundle, other.recoveryKey),
        throwsA(isA<InvalidRecoveryKey>()),
      );
      await expectLater(
        crypto.unlockWithRecovery(acc.bundle, 'nope'),
        throwsA(isA<InvalidRecoveryKey>()),
      );
    },
  );

  test('forged publicKey is refused on both unlock paths', () async {
    final other = await crypto.create('battery staple');
    final forged = AccountBundle.fromJson({
      ...acc.bundle.toJson(),
      'publicKey': b64(other.bundle.publicKey),
    });
    await expectLater(
      crypto.unlock(forged, 'correct horse'),
      throwsA(isA<WrongPassword>()),
    );
    await expectLater(
      crypto.unlockWithRecovery(forged, acc.recoveryKey),
      throwsA(isA<InvalidRecoveryKey>()),
    );
  });

  test('changePassword and rotateRecoveryKey keep unknown fields', () async {
    final withExtra = AccountBundle.fromJson({
      'future': [1, 2],
      ...acc.bundle.toJson(),
    });
    final u = await crypto.unlock(withExtra, 'correct horse');

    final changed = await crypto.changePassword(u, withExtra, 'battery staple');
    expect(
      without(changed.bundle, ['salt', 'kdf', 'wrappedUserKey']),
      without(withExtra, ['salt', 'kdf', 'wrappedUserKey']),
    );
    expect(changed.bundle.salt, isNot(withExtra.salt));
    expect(changed.bundle.toJson()['future'], [1, 2]);
    expect(
      (await crypto.unlock(changed.bundle, 'battery staple')).userKey,
      u.userKey,
    );
    await expectLater(
      crypto.unlock(changed.bundle, 'correct horse'),
      throwsA(isA<WrongPassword>()),
    );
    expect(
      (await crypto.unlockWithRecovery(
        changed.bundle,
        acc.recoveryKey,
      )).userKey,
      u.userKey,
    );
    expect(
      changed.authKey,
      (await deriveMasterKeys(
        'battery staple',
        changed.bundle.salt,
        KdfParams.testing,
      )).authKey,
    );

    final rotated = await crypto.rotateRecoveryKey(u, withExtra);
    expect(
      without(rotated.bundle, ['wrappedUserKeyByRecovery']),
      without(withExtra, ['wrappedUserKeyByRecovery']),
    );
    expect(
      (await crypto.unlockWithRecovery(
        rotated.bundle,
        rotated.recoveryKey,
      )).userKey,
      u.userKey,
    );
    await expectLater(
      crypto.unlockWithRecovery(rotated.bundle, acc.recoveryKey),
      throwsA(isA<InvalidRecoveryKey>()),
    );
    expect(
      await recoveryAuthKey(RecoveryKey.decode(rotated.recoveryKey)),
      rotated.recoveryAuthKey,
    );
  });

  test('production AccountCrypto refuses a testing-KDF bundle', () async {
    expect(
      () => AccountCrypto(kdf: KdfParams.testing),
      throwsA(isA<WeakKdf>()),
    );
    await expectLater(
      AccountCrypto().unlock(acc.bundle, 'correct horse'),
      throwsA(isA<WeakKdf>()),
    );
  });

  test('malformed bundles throw FormatException', () {
    final j = acc.bundle.toJson();
    for (final bad in <Object?>[
      'x',
      {...j, 'salt': b64(List.filled(15, 0))},
      {...j, 'publicKey': b64(List.filled(31, 0))},
      Map.of(j)..remove('wrappedPrivateKey'),
      {...j, 'kdf': 'argon2id'},
    ]) {
      expect(() => AccountBundle.fromJson(bad), throwsFormatException);
    }
  });
}
