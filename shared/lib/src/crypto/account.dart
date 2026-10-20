// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart' show constantTimeBytesEquality;

import '../bytes.dart';
import '../util/json_reader.dart';
import '../util/secure.dart';
import 'cipher.dart';
import 'envelope.dart';
import 'errors.dart';
import 'kdf.dart';
import 'recovery_key.dart';

/// The account's wrapped keys as stored on the server. KDF bounds are
/// checked by whoever derives from [kdf], not on parse.
class AccountBundle {
  AccountBundle({
    required this.salt,
    required this.kdf,
    required this.wrappedUserKey,
    required this.wrappedUserKeyByRecovery,
    required this.publicKey,
    required this.wrappedPrivateKey,
    this.extra = const {},
  });

  factory AccountBundle.fromJson(Object? json) {
    final r = JsonReader(json, 'accountBundle');
    return AccountBundle(
      salt: r.bytes('salt', length: 16),
      kdf: KdfParams.fromJson(r.object('kdf')),
      wrappedUserKey: Envelope.fromJson(r.object('wrappedUserKey')),
      wrappedUserKeyByRecovery: Envelope.fromJson(
        r.object('wrappedUserKeyByRecovery'),
      ),
      publicKey: r.bytes('publicKey', length: 32),
      wrappedPrivateKey: Envelope.fromJson(r.object('wrappedPrivateKey')),
      extra: r.extra(_known),
    );
  }

  static const _known = {
    'salt',
    'kdf',
    'wrappedUserKey',
    'wrappedUserKeyByRecovery',
    'publicKey',
    'wrappedPrivateKey',
  };

  final Uint8List salt;
  final KdfParams kdf;
  final Envelope wrappedUserKey;
  final Envelope wrappedUserKeyByRecovery;
  final Uint8List publicKey;
  final Envelope wrappedPrivateKey;
  final Map<String, Object?> extra;

  AccountBundle copyWith({
    Uint8List? salt,
    KdfParams? kdf,
    Envelope? wrappedUserKey,
    Envelope? wrappedUserKeyByRecovery,
  }) => AccountBundle(
    salt: salt ?? this.salt,
    kdf: kdf ?? this.kdf,
    wrappedUserKey: wrappedUserKey ?? this.wrappedUserKey,
    wrappedUserKeyByRecovery:
        wrappedUserKeyByRecovery ?? this.wrappedUserKeyByRecovery,
    publicKey: publicKey,
    wrappedPrivateKey: wrappedPrivateKey,
    extra: extra,
  );

  Map<String, Object?> toJson() => {
    ...extra,
    'salt': b64(salt),
    'kdf': kdf.toJson(),
    'wrappedUserKey': wrappedUserKey.toJson(),
    'wrappedUserKeyByRecovery': wrappedUserKeyByRecovery.toJson(),
    'publicKey': b64(publicKey),
    'wrappedPrivateKey': wrappedPrivateKey.toJson(),
  };
}

class NewAccount {
  NewAccount({
    required this.bundle,
    required this.authKey,
    required this.recoveryAuthKey,
    required this.recoveryKey,
    required this.unlocked,
  });

  final AccountBundle bundle;
  final Uint8List authKey;
  final Uint8List recoveryAuthKey;

  /// Encoded text, shown once to the user.
  final String recoveryKey;
  final UnlockedAccount unlocked;
}

class UnlockedAccount {
  UnlockedAccount({
    required this.userKey,
    required this.keyPair,
    required this.bundle,
  });

  final Uint8List userKey;
  final SimpleKeyPair keyPair;
  final AccountBundle bundle;
}

class AccountCrypto {
  AccountCrypto({this.kdf = KdfParams.defaults, this.allowTestingKdf = false}) {
    kdf.ensureAcceptable(allowTesting: allowTestingKdf);
  }

  static const minPasswordLength = 8;
  final KdfParams kdf; // the instance KDF used for new wraps
  final bool allowTestingKdf; // tests only
  static final _x25519 = X25519();

  Future<NewAccount> create(String password) async {
    _checkPassword(password);
    final salt = secureBytes(16),
        userKey = secureBytes(32),
        seed = secureBytes(32);
    final recovery = RecoveryKey.generate();
    final keys = await deriveMasterKeys(password, salt, kdf);
    final keyPair = await _x25519.newKeyPairFromSeed(seed);
    final bundle = AccountBundle(
      salt: salt,
      kdf: kdf,
      wrappedUserKey: await SymmetricCipher.encrypt(
        keys.encKey,
        userKey,
        KeyIds.master,
      ),
      wrappedUserKeyByRecovery: await SymmetricCipher.encrypt(
        await recoveryWrapKey(recovery),
        userKey,
        KeyIds.recovery,
      ),
      publicKey: Uint8List.fromList((await keyPair.extractPublicKey()).bytes),
      wrappedPrivateKey: await SymmetricCipher.encrypt(
        userKey,
        seed,
        KeyIds.userX25519,
      ),
    );
    return NewAccount(
      bundle: bundle,
      authKey: keys.authKey,
      recoveryAuthKey: await recoveryAuthKey(recovery),
      recoveryKey: RecoveryKey.encode(recovery),
      unlocked: UnlockedAccount(
        userKey: userKey,
        keyPair: keyPair,
        bundle: bundle,
      ),
    );
  }

  Future<UnlockedAccount> unlock(AccountBundle bundle, String password) async {
    // Before any derivation: a hostile server may serve a weak or huge KDF.
    bundle.kdf.ensureAcceptable(allowTesting: allowTestingKdf);
    final keys = await deriveMasterKeys(password, bundle.salt, bundle.kdf);
    try {
      return await _finish(
        bundle,
        await SymmetricCipher.decrypt(keys.encKey, bundle.wrappedUserKey),
      );
    } on DecryptionFailed {
      throw const WrongPassword();
    }
  }

  Future<UnlockedAccount> unlockWithRecovery(
    AccountBundle bundle,
    String recoveryKey,
  ) async {
    final recovery = RecoveryKey.decode(recoveryKey);
    try {
      final userKey = await SymmetricCipher.decrypt(
        await recoveryWrapKey(recovery),
        bundle.wrappedUserKeyByRecovery,
      );
      return await _finish(bundle, userKey);
    } on DecryptionFailed {
      throw const InvalidRecoveryKey();
    }
  }

  /// The device kept the userKey (biometric unlock): same rebuild and public key check as unlock.
  Future<UnlockedAccount> unlockWithUserKey(
    AccountBundle bundle,
    Uint8List userKey,
  ) async {
    try {
      return await _finish(bundle, userKey);
    } on DecryptionFailed {
      throw const WrongPassword();
    }
  }

  /// The rebuilt public key must equal bundle.publicKey: a server cannot pair our private key with its own public key.
  Future<UnlockedAccount> _finish(
    AccountBundle bundle,
    Uint8List userKey,
  ) async {
    final seed = await SymmetricCipher.decrypt(
      userKey,
      bundle.wrappedPrivateKey,
    );
    final keyPair = await _x25519.newKeyPairFromSeed(seed);
    if (!constantTimeBytesEquality.equals(
      (await keyPair.extractPublicKey()).bytes,
      bundle.publicKey,
    )) {
      throw const DecryptionFailed();
    }
    return UnlockedAccount(userKey: userKey, keyPair: keyPair, bundle: bundle);
  }

  /// New salt, instance KDF, new wrappedUserKey; every other field (unknown ones included) kept.
  Future<({AccountBundle bundle, Uint8List authKey})> changePassword(
    UnlockedAccount unlocked,
    AccountBundle bundle,
    String newPassword,
  ) async {
    _checkPassword(newPassword);
    final salt = secureBytes(16);
    final keys = await deriveMasterKeys(newPassword, salt, kdf);
    final wrapped = await SymmetricCipher.encrypt(
      keys.encKey,
      unlocked.userKey,
      KeyIds.master,
    );
    return (
      bundle: bundle.copyWith(salt: salt, kdf: kdf, wrappedUserKey: wrapped),
      authKey: keys.authKey,
    );
  }

  /// Only wrappedUserKeyByRecovery changes.
  Future<
    ({AccountBundle bundle, Uint8List recoveryAuthKey, String recoveryKey})
  >
  rotateRecoveryKey(UnlockedAccount unlocked, AccountBundle bundle) async {
    final recovery = RecoveryKey.generate();
    final wrapped = await SymmetricCipher.encrypt(
      await recoveryWrapKey(recovery),
      unlocked.userKey,
      KeyIds.recovery,
    );
    return (
      bundle: bundle.copyWith(wrappedUserKeyByRecovery: wrapped),
      recoveryAuthKey: await recoveryAuthKey(recovery),
      recoveryKey: RecoveryKey.encode(recovery),
    );
  }

  void _checkPassword(String password) {
    if (passwordLength(password) < minPasswordLength) {
      throw const WeakPassword();
    }
  }
}
