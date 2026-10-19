// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'local_mirror.dart';

/// A payload that does not open or parse: wrong key or tampered, unknown envelope, malformed body.
bool isUnreadable(Exception e) =>
    e is DecryptionFailed || e is UnsupportedEnvelope || e is FormatException;

/// One JSON document sealed under the user key in a kv slot; its seq counts the writes.
class SealedKv {
  SealedKv(this._mirror, this._slot, this._aad);

  final LocalMirror _mirror;
  final KvKey _slot;
  final PayloadAad _aad;
  Uint8List? _key;
  int _writes = 0;

  /// Hands the stored document, if any, to [read]. False when it is unreadable, [read]'s
  /// [FormatException] included: the write count restarts.
  Future<bool> load(
    Uint8List userKey,
    void Function(Map<String, Object?> json) read,
  ) async {
    _key = userKey;
    _writes = 0;
    final stored = _mirror.getKv(_slot);
    if (stored == null) return true;
    try {
      final opened = await PayloadCrypto.open(
        _aad,
        Envelope.fromJson(jsonDecode(stored)),
        userKey,
      );
      read(opened.json);
      _writes = opened.seq ?? 0;
      return true;
    } on Exception catch (e) {
      if (!isUnreadable(e)) rethrow;
      return false;
    }
  }

  Future<void> save(Map<String, Object?> json) async {
    final key = _key;
    if (key == null) throw StateError('${_slot.name} is not loaded');
    final sealed = await PayloadCrypto.seal(
      _aad,
      json,
      key,
      KeyIds.user,
      seq: ++_writes,
    );
    _mirror.setKv(_slot, jsonEncode(sealed.toJson()));
  }

  /// On lock: forgets the user key.
  void close() {
    _key = null;
    _writes = 0;
  }
}
