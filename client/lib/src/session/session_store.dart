// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

/// The OS keystore, behind an interface so tests use a map.
abstract interface class SecureKv {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// macOS login keychain (no data-protection keychain: it needs an entitlement unsigned builds lack),
/// Windows Credential Manager.
class FlutterSecureKv implements SecureKv {
  FlutterSecureKv([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

@immutable
class StoredSession {
  const StoredSession({
    required this.serverUrl,
    required this.userId,
    required this.deviceId,
    required this.email,
    required this.refreshToken,
    required this.isInstanceOwner,
    this.displayName,
  });

  /// Strict: anything malformed is a [FormatException].
  factory StoredSession.fromJson(Object? json) => switch (json) {
    {
      'serverUrl': final String serverUrl,
      'userId': final String userId,
      'deviceId': final String deviceId,
      'email': final String email,
      'refreshToken': final String refreshToken,
      'isInstanceOwner': final bool isInstanceOwner,
    }
        when isUuid(userId) && isUuid(deviceId) =>
      StoredSession(
        serverUrl: Uri.parse(serverUrl),
        userId: userId,
        deviceId: deviceId,
        email: email,
        refreshToken: refreshToken,
        isInstanceOwner: isInstanceOwner,
        displayName: switch (json['displayName']) {
          final String name => name,
          null => null,
          _ => throw const FormatException('session.displayName: not a string'),
        },
      ),
    _ => throw const FormatException('session: malformed'),
  };

  final Uri serverUrl;
  final String userId;
  final String deviceId;
  final String email;
  final String refreshToken;
  final bool isInstanceOwner;
  final String? displayName;

  Map<String, Object?> toJson() => {
    'serverUrl': '$serverUrl',
    'userId': userId,
    'deviceId': deviceId,
    'email': email,
    'refreshToken': refreshToken,
    'isInstanceOwner': isInstanceOwner,
    'displayName': displayName,
  };

  @override
  bool operator ==(Object other) =>
      other is StoredSession && mapEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hash(
    serverUrl,
    userId,
    deviceId,
    email,
    refreshToken,
    isInstanceOwner,
    displayName,
  );
}

/// The signed-in session of this machine. Missing or unreadable means logged out.
class SessionStore {
  SessionStore(this.kv);

  static const key = 'unfeudal.session.v1';

  final SecureKv kv;

  Future<StoredSession?> load() async {
    try {
      final raw = await kv.read(key);
      return raw == null ? null : StoredSession.fromJson(jsonDecode(raw));
    } on Exception {
      return null; // keystore error or malformed value: signed out, never a crash
    }
  }

  Future<void> save(StoredSession session) =>
      kv.write(key, jsonEncode(session.toJson()));

  Future<void> saveRefreshToken(String refreshToken) =>
      _update((s) => {...s, 'refreshToken': refreshToken});

  Future<void> saveDisplayName(String? displayName) =>
      _update((s) => {...s, 'displayName': displayName});

  Future<void> clear() => kv.delete(key);

  Future<void> _update(
    Map<String, Object?> Function(Map<String, Object?>) change,
  ) async {
    final current = await load();
    if (current == null) return;
    await save(StoredSession.fromJson(change(current.toJson())));
  }
}
