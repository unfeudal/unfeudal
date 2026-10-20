// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'session_store.dart';

/// Platform side (the native runners): a 32-byte secret that only the hardware releases, after the OS prompt.
abstract interface class BiometricBackend {
  Future<bool> available();

  /// Null when the user cancels or the secret is gone. [create] makes it first.
  Future<Uint8List?> secret({required bool create, required String reason});
  Future<void> delete();
}

class ChannelBiometricBackend implements BiometricBackend {
  const ChannelBiometricBackend();
  static const _channel = MethodChannel('fr.unfeudal/biometric');
  @override
  Future<bool> available() async {
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<Uint8List?> secret({
    required bool create,
    required String reason,
  }) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('secret', {
        'create': create,
        'reason': reason,
      });
      return bytes == null || bytes.length != 32 ? null : bytes;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _channel.invokeMethod<void>('delete');
    } on PlatformException {
      // nothing to delete
    }
  }
}

class BiometricUnlock {
  BiometricUnlock(this.kv, this.backend);
  final SecureKv kv;
  final BiometricBackend backend;
  static const storageKey = 'biometric.wrappedUserKey';
  static final _aad = utf8.encode('biometric/userKey');

  Future<bool> isEnabled() async => await kv.read(storageKey) != null;

  Future<bool> enable(Uint8List userKey, {required String reason}) async {
    if (!await backend.available()) return false;
    final secret = await backend.secret(create: true, reason: reason);
    if (secret == null) return false;
    final wrapped = await SymmetricCipher.encrypt(
      secret,
      userKey,
      KeyIds.biometric,
      aad: _aad,
    );
    await kv.write(storageKey, jsonEncode(wrapped.toJson()));
    return true;
  }

  /// Null when not enabled or cancelled. A wrap the hardware secret no longer opens is wiped.
  Future<Uint8List?> unlock({required String reason}) async {
    final raw = await kv.read(storageKey);
    if (raw == null) return null;
    final secret = await backend.secret(create: false, reason: reason);
    if (secret == null) return null;
    try {
      return await SymmetricCipher.decrypt(
        secret,
        Envelope.fromJson(jsonDecode(raw)),
        aad: _aad,
      );
    } on DecryptionFailed {
      await disable();
      return null;
    } on FormatException {
      await disable();
      return null;
    }
  }

  Future<void> disable() async {
    await kv.delete(storageKey);
    await backend.delete();
  }
}

/// The biometric unlock as the server allows it: offered only under its `biometric_unlock` flag, and a
/// stored wrap is wiped once the flag goes off.
class BiometricGate {
  BiometricGate(this._unlock, {required this._allowed, required this._reason});

  final BiometricUnlock _unlock;
  final bool Function() _allowed;
  // The OS prompt's text, in the current language.
  final String Function() _reason;
  bool _wasAllowed = true;

  Future<bool> isEnabled() => _unlock.isEnabled();

  /// Hardware present, the server allows it, and the OS offers it.
  Future<bool> isAvailable() async =>
      _allowed() && await _unlock.backend.available();

  /// A stored wrap the server still allows; a wrap it no longer allows is wiped.
  Future<bool> isOffered() async {
    if (!await _unlock.isEnabled()) return false;
    if (_allowed()) return true;
    await _unlock.disable();
    return false;
  }

  Future<bool> enable(Uint8List userKey) async =>
      await isAvailable() && await _unlock.enable(userKey, reason: _reason());

  /// The stored userKey once the OS prompt is passed; null when cancelled.
  Future<Uint8List?> userKey() => _unlock.unlock(reason: _reason());

  Future<void> disable() => _unlock.disable();

  /// Wipes a stored wrap when the server turned the flag off, once per change of the flag.
  void checkFlag() {
    final allowed = _allowed();
    if (_wasAllowed && !allowed) unawaited(_unlock.disable());
    _wasAllowed = allowed;
  }
}
