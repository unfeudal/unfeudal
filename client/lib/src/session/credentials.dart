// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/api_client.dart';
import '../storage/local_mirror.dart';

/// The account bundle cached at sign-in and after each change the server accepted.
extension CachedBundle on LocalMirror {
  ({AccountBundle bundle, int bundleVersion}) get cachedBundle {
    final raw = getKv(KvKey.bundle) ?? (throw StateError('no cached bundle'));
    final json = jsonDecode(raw) as Map<String, Object?>;
    return (
      bundle: AccountBundle.fromJson(json['bundle']),
      bundleVersion: json['bundleVersion']! as int,
    );
  }

  void cacheBundle(AccountBundle bundle, int bundleVersion) => setKv(
    KvKey.bundle,
    jsonEncode({'bundle': bundle.toJson(), 'bundleVersion': bundleVersion}),
  );
}

/// The signed-in account's password and recovery kit. Each change proves the current password locally
/// before anything is sent, and caches the bundle the server accepted.
class Credentials {
  Credentials({
    required this._crypto,
    required this._api,
    required this._mirror,
    required this._serverHas,
  });

  final AccountCrypto _crypto;
  // The client and the mirror are replaced at each sign-in.
  final ApiClient Function() _api;
  final LocalMirror Function() _mirror;
  final bool Function(Flag flag) _serverHas;

  /// The account's X25519 public key, from the cached bundle (signed in or unlocked).
  Uint8List get publicKey => _mirror().cachedBundle.bundle.publicKey;

  /// The userKey stays the same, so a biometric wrap stays valid.
  Future<void> changePassword(String current, String next) async {
    await _changePassword(current, next);
  }

  /// Password change, then a new recovery kit when the server allows it (null otherwise).
  Future<String?> securityReset(String current, String next) async {
    final changed = await _changePassword(current, next);
    return _serverHas(Flag.recoveryKit)
        ? _rotateRecoveryKit(changed.unlocked, changed.authKey)
        : null;
  }

  /// New recovery key text; the server stores the new wrap (compare-and-swap on the bundle version).
  Future<String> regenerateRecoveryKit(String password) async {
    final proved = await _crypto.unlockWithAuthKey(
      _mirror().cachedBundle.bundle,
      password,
    );
    return _rotateRecoveryKit(proved.unlocked, proved.authKey);
  }

  // Returns the unlocked account and the new password's authKey, for a recovery kit right after.
  Future<({UnlockedAccount unlocked, Uint8List authKey})> _changePassword(
    String current,
    String next,
  ) async {
    final (:bundle, :bundleVersion) = _mirror().cachedBundle;
    // WrongPassword and WeakPassword throw here, before anything is sent.
    final proved = await _crypto.unlockWithAuthKey(bundle, current);
    final changed = await _crypto.changePassword(proved.unlocked, bundle, next);
    await _api().changePassword(
      currentAuthKey: proved.authKey,
      bundle: changed.bundle,
      bundleVersion: bundleVersion,
      authKey: changed.authKey,
    );
    _mirror().cacheBundle(changed.bundle, bundleVersion + 1);
    return (unlocked: proved.unlocked, authKey: changed.authKey);
  }

  // authKey proves the password of the cached bundle.
  Future<String> _rotateRecoveryKit(
    UnlockedAccount unlocked,
    Uint8List authKey,
  ) async {
    final (:bundle, :bundleVersion) = _mirror().cachedBundle;
    final rotated = await _crypto.rotateRecoveryKey(unlocked, bundle);
    await _api().changeRecoveryKit(
      currentAuthKey: authKey,
      bundle: rotated.bundle,
      bundleVersion: bundleVersion,
      recoveryAuthKey: rotated.recoveryAuthKey,
    );
    _mirror().cacheBundle(rotated.bundle, bundleVersion + 1);
    return rotated.recoveryKey;
  }
}
