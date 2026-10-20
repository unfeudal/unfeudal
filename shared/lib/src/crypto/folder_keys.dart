// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart' show constantTimeBytesEquality;

import '../bytes.dart';
import '../util/json_reader.dart';
import '../util/secure.dart';
import 'cipher.dart';
import 'envelope.dart';
import 'errors.dart';
import 'payload_crypto.dart';
import 'sealed_box.dart';

/// Plaintext keys of one folder version; never on the wire.
class FolderKeys {
  FolderKeys(this.version, this.metaKey, this.secretKey) {
    if (version < 1 ||
        metaKey.length != 32 ||
        (secretKey != null && secretKey!.length != 32)) {
      throw ArgumentError('invalid folder keys');
    }
  }

  factory FolderKeys.generate(int version) =>
      FolderKeys(version, secureBytes(32), secureBytes(32));

  final int version;
  final Uint8List metaKey; // `view`
  final Uint8List? secretKey; // `connect`; null when not held
}

/// Folder keys sealed to one member's X25519 public key.
class WrappedFolderKeys {
  WrappedFolderKeys({
    this.userId,
    required this.version,
    required this.meta,
    this.secret,
    this.extra = const {},
  });

  factory WrappedFolderKeys.fromJson(Object? json) {
    final r = JsonReader(json, 'wrappedFolderKeys');
    final secret = r.opt<Map<String, Object?>>('secret');
    return WrappedFolderKeys(
      userId: r.optUuid('userId'),
      version: r.integer('version', min: 1),
      meta: Envelope.fromJson(r.object('meta')),
      secret: secret == null ? null : Envelope.fromJson(secret),
      extra: r.extra(const {'userId', 'version', 'meta', 'secret'}),
    );
  }

  final String? userId; // omitted on the sync wire
  final int version;
  final Envelope meta;
  final Envelope? secret;
  final Map<String, Object?> extra;

  static Future<WrappedFolderKeys> wrap(
    FolderKeys keys, {
    required String folderId,
    required List<int> recipientPublicKey,
    String? userId,
    bool withSecret = true,
  }) async {
    String label(PayloadPart p) => KeyIds.folder(folderId, keys.version, p);
    return WrappedFolderKeys(
      userId: userId,
      version: keys.version,
      meta: await SealedBox.seal(
        keys.metaKey,
        recipientPublicKey,
        label(PayloadPart.meta),
      ),
      secret: withSecret && keys.secretKey != null
          ? await SealedBox.seal(
              keys.secretKey!,
              recipientPublicKey,
              label(PayloadPart.secret),
            )
          : null,
    );
  }

  /// Labels must be `folder:<folderId>:v<version>:meta|secret`, else SealedBox.open throws KeyLabelMismatch.
  Future<FolderKeys> unwrap(String folderId, SimpleKeyPair keyPair) async {
    String label(PayloadPart p) => KeyIds.folder(folderId, version, p);
    final metaKey = await SealedBox.open(
      meta,
      keyPair,
      label(PayloadPart.meta),
    );
    final secretKey = secret == null
        ? null
        : await SealedBox.open(secret!, keyPair, label(PayloadPart.secret));
    return FolderKeys(version, metaKey, secretKey);
  }

  Map<String, Object?> toJson() => {
    ...extra,
    if (userId != null) 'userId': userId,
    'version': version,
    'meta': meta.toJson(),
    'secret': secret?.toJson(),
  };
}

/// Previous folder key versions, sealed under the current ones.
class FolderKeyHistory {
  FolderKeyHistory({
    required this.version,
    required this.meta,
    this.secret,
    this.extra = const {},
  });

  factory FolderKeyHistory.fromJson(Object? json) {
    final r = JsonReader(json, 'folderKeyHistory');
    final secret = r.opt<Map<String, Object?>>('secret');
    return FolderKeyHistory(
      version: r.integer('version', min: 1),
      meta: Envelope.fromJson(r.object('meta')),
      secret: secret == null ? null : Envelope.fromJson(secret),
      extra: r.extra(const {'version', 'meta', 'secret'}),
    );
  }

  final int version;
  final Envelope meta;
  final Envelope? secret;
  final Map<String, Object?> extra;

  static final _metaAad = utf8.encode('history/meta');
  static final _secretAad = utf8.encode('history/secret');

  static Future<FolderKeyHistory> seal(
    FolderKeys current,
    List<FolderKeys> previous, {
    required String folderId,
  }) async {
    if (previous.any((k) => k.version >= current.version)) {
      throw ArgumentError('history must be older than current');
    }
    final metaList = [
      for (final k in previous) {'version': k.version, 'meta': b64(k.metaKey)},
    ];
    final secretList = [
      for (final k in previous)
        if (k.secretKey != null)
          {'version': k.version, 'secret': b64(k.secretKey!)},
    ];
    return FolderKeyHistory(
      version: current.version,
      meta: await SymmetricCipher.encrypt(
        current.metaKey,
        utf8.encode(jsonEncode(metaList)),
        KeyIds.folder(folderId, current.version, PayloadPart.meta),
        aad: _metaAad,
      ),
      secret: current.secretKey == null
          ? null
          : await SymmetricCipher.encrypt(
              current.secretKey!,
              utf8.encode(jsonEncode(secretList)),
              KeyIds.folder(folderId, current.version, PayloadPart.secret),
              aad: _secretAad,
            ),
    );
  }

  /// Checks `version` and both keyIds against [current] and [folderId] (KeyLabelMismatch), then decrypts.
  /// Secret keys are filled only when [current] holds its secret key and the secret part is present.
  Future<List<FolderKeys>> open(
    FolderKeys current, {
    required String folderId,
  }) async {
    final metaId = KeyIds.folder(folderId, current.version, PayloadPart.meta);
    final secretId = KeyIds.folder(
      folderId,
      current.version,
      PayloadPart.secret,
    );
    if (version != current.version) throw KeyLabelMismatch('history v$version');
    if (meta.keyId != metaId) throw KeyLabelMismatch(meta.keyId);
    if (secret != null && secret!.keyId != secretId) {
      throw KeyLabelMismatch(secret!.keyId);
    }
    final metas = _entries(
      await SymmetricCipher.decrypt(current.metaKey, meta, aad: _metaAad),
      'meta',
      current.version,
    );
    final secrets = secret == null || current.secretKey == null
        ? const <int, Uint8List>{}
        : _entries(
            await SymmetricCipher.decrypt(
              current.secretKey!,
              secret!,
              aad: _secretAad,
            ),
            'secret',
            current.version,
          );
    return [
      for (final e in metas.entries) FolderKeys(e.key, e.value, secrets[e.key]),
    ]..sort((a, b) => a.version.compareTo(b.version));
  }

  // A JSON list of `{version (1..current-1, unique), <field>: b64(32 bytes)}`, else FormatException.
  static Map<int, Uint8List> _entries(
    List<int> plain,
    String field,
    int current,
  ) {
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! List<Object?>) {
      throw const FormatException('history: not a JSON list');
    }
    final entries = <int, Uint8List>{};
    for (final element in decoded) {
      final r = JsonReader(element, 'history');
      final version = r.integer('version', min: 1, max: current - 1);
      final key = r.bytes(field, length: 32);
      if (entries.containsKey(version)) {
        throw const FormatException('history.version: duplicate');
      }
      entries[version] = key;
    }
    return entries;
  }

  Map<String, Object?> toJson() => {
    ...extra,
    'version': version,
    'meta': meta.toJson(),
    'secret': secret?.toJson(),
  };
}

/// A served key is accepted only if it equals, or continues through its opened history, the key already held,
/// for the meta key and (when held) the secret key. Older served versions are a rollback.
bool continues(FolderKeys held, FolderKeys served, List<FolderKeys> history) {
  if (served.version < held.version) return false;
  final match = served.version == held.version
      ? served
      : history.where((k) => k.version == held.version).firstOrNull;
  if (match == null ||
      !constantTimeBytesEquality.equals(match.metaKey, held.metaKey)) {
    return false;
  }
  if (held.secretKey == null) return true;
  return match.secretKey != null &&
      constantTimeBytesEquality.equals(match.secretKey!, held.secretKey!);
}
