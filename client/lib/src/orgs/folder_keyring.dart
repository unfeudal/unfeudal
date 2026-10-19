// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart' show constantTimeBytesEquality;
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../storage/local_mirror.dart';

/// Folder keys this device holds, sealed under the user key in `kv.keyring`.
class FolderKeyring {
  FolderKeyring(this.mirror);
  final LocalMirror mirror;
  Uint8List? _userKey;
  int _writes = 0;
  final _keys = <String, Map<int, FolderKeys>>{}; // folderId → version → keys

  /// false: kv.keyring did not open (reported by the caller); the keyring restarts empty.
  Future<bool> load(Uint8List userKey) async {
    _userKey = userKey;
    _keys.clear();
    _writes = 0;
    final stored = mirror.getKv(KvKey.keyring);
    if (stored == null) return true;
    try {
      final opened = await PayloadCrypto.open(
        keyringAad,
        Envelope.fromJson(jsonDecode(stored)),
        userKey,
      );
      _readFolders(opened.json);
      _writes = opened.seq ?? 0;
      return true;
    } on DecryptionFailed {
      _keys.clear();
    } on UnsupportedEnvelope {
      _keys.clear();
    } on FormatException {
      _keys.clear();
    }
    return false;
  }

  Future<void> save() async {
    final key = _userKey;
    if (key == null) throw StateError('keyring is not loaded');
    final json = {
      'folders': {
        for (final MapEntry(key: folderId, value: versions) in _keys.entries)
          folderId: [
            for (final k in versions.values)
              {
                'version': k.version,
                'meta': b64(k.metaKey),
                'secret': k.secretKey == null ? null : b64(k.secretKey!),
              },
          ],
      },
    };
    final sealed = await PayloadCrypto.seal(
      keyringAad,
      json,
      key,
      KeyIds.user,
      seq: ++_writes,
    );
    mirror.setKv(KvKey.keyring, jsonEncode(sealed.toJson()));
  }

  /// The highest version held.
  FolderKeys? current(String folderId) {
    final versions = _keys[folderId];
    if (versions == null || versions.isEmpty) return null;
    return versions[versions.keys.reduce((a, b) => a > b ? a : b)];
  }

  FolderKeys? keyFor(String folderId, int version) => _keys[folderId]?[version];

  /// Keys this device generated (new folder, rotation).
  Future<void> put(String folderId, FolderKeys keys) {
    _keys.putIfAbsent(folderId, () => {})[keys.version] = keys;
    return save();
  }

  /// On lock: forgets the user key and the keys.
  void close() {
    _userKey = null;
    _keys.clear();
    _writes = 0;
  }

  /// Unwraps every served row; keeps a key only if it equals, or continues through its history, the key held.
  /// Returns the folders whose served key was refused (the held key is kept, the UI alerts).
  Future<Set<String>> apply(OrgBlock block, SimpleKeyPair keyPair) async {
    final refused = <String>{};
    final histories = {for (final h in block.keyHistory) h.folderId: h};
    for (final row in block.wrappedKeys) {
      try {
        final served = await row.keys.unwrap(
          row.folderId,
          keyPair,
        ); // labels: KeyLabelMismatch
        final h = histories[row.folderId];
        final older = h != null && h.version == served.version
            ? await h.history.open(served, folderId: row.folderId)
            : const <FolderKeys>[];
        final held = current(row.folderId);
        if (held != null) {
          // Losing connect is not a swap: compare meta keys only when the served key has no secret part.
          final comparable = served.secretKey == null
              ? FolderKeys(held.version, held.metaKey, null)
              : held;
          if (!continues(comparable, served, older)) {
            refused.add(row.folderId);
            continue;
          }
        }
        final versions = _keys.putIfAbsent(row.folderId, () => {});
        for (final k in [...older, served]) {
          final had = versions[k.version];
          // A held version is replaced only to gain its secret part (connect granted at the same version).
          if (had == null ||
              (had.secretKey == null &&
                  k.secretKey != null &&
                  constantTimeBytesEquality.equals(had.metaKey, k.metaKey))) {
            versions[k.version] = k;
          }
        }
      } on Exception catch (e) {
        if (e is KeyLabelMismatch ||
            e is DecryptionFailed ||
            e is UnsupportedEnvelope ||
            e is FormatException) {
          refused.add(row.folderId);
        } else {
          rethrow;
        }
      }
    }
    await save();
    return refused;
  }

  void _readFolders(Map<String, Object?> json) {
    if (json case {'folders': final Map<String, Object?> folders}) {
      for (final MapEntry(key: folderId, value: list) in folders.entries) {
        if (list is! List<Object?>) {
          throw const FormatException('keyring: folder');
        }
        for (final k in list) {
          if (k case {
            'version': final int version,
            'meta': final String meta,
            'secret': final String? secret,
          }) {
            _keys.putIfAbsent(folderId, () => {})[version] = FolderKeys(
              version,
              unb64(meta),
              secret == null ? null : unb64(secret),
            );
          } else {
            throw const FormatException('keyring: key');
          }
        }
      }
    } else {
      throw const FormatException('keyring: unexpected body');
    }
  }
}
