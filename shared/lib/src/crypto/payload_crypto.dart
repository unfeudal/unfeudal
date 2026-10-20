// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:typed_data';

import '../protocol/item.dart';
import 'cipher.dart';
import 'envelope.dart';
import 'errors.dart';

enum PayloadPart { meta, secret }

/// Binds a payload to its item: a server that moves, re-types or re-scopes
/// the item makes decryption fail.
class PayloadAad {
  const PayloadAad({
    required this.itemId,
    required this.part,
    required this.type,
    required this.scope,
    required this.orgId,
    required this.folderId,
  });

  factory PayloadAad.of(Item item, PayloadPart part) => PayloadAad(
    itemId: item.id,
    part: part,
    type: item.type,
    scope: item.scope,
    orgId: item.orgId,
    folderId: item.folderId,
  );

  final String itemId;
  final PayloadPart part;
  final String type;
  final ItemScope scope;
  final String? orgId;
  final String? folderId;

  Uint8List get bytes => utf8.encode(
    '$itemId/${part.name}/$type/${scope.name}/${orgId ?? ''}/${folderId ?? ''}',
  );
}

class OpenedPayload {
  const OpenedPayload(this.json, this.seq);

  final Map<String, Object?> json; // without _seq
  final int? seq; // null = no mark yet
}

abstract final class PayloadCrypto {
  static Future<Envelope> seal(
    PayloadAad aad,
    Map<String, Object?> json,
    List<int> key,
    String keyId, {
    required int seq,
  }) {
    if (seq < 1) throw ArgumentError.value(seq, 'seq', 'must be >= 1');
    if (json.containsKey('_seq')) throw ArgumentError('_seq is reserved');
    if (!_keyIdFits(aad, keyId)) {
      throw ArgumentError.value(keyId, 'keyId', 'does not match the item');
    }
    return SymmetricCipher.encrypt(
      key,
      utf8.encode(jsonEncode({...json, '_seq': seq})),
      keyId,
      aad: aad.bytes,
    );
  }

  static Future<OpenedPayload> open(
    PayloadAad aad,
    Envelope envelope,
    List<int> key,
  ) async {
    if (!_keyIdFits(aad, envelope.keyId)) throw const DecryptionFailed();
    final plain = await SymmetricCipher.decrypt(key, envelope, aad: aad.bytes);
    // Invalid UTF-8 and invalid JSON both throw FormatException.
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('payload is not a JSON object');
    }
    final json = Map<String, Object?>.of(decoded);
    if (!json.containsKey('_seq')) return OpenedPayload(json, null);
    final seq = json.remove('_seq');
    if (seq is! int || seq < 1) {
      throw const FormatException('_seq must be an integer >= 1');
    }
    return OpenedPayload(json, seq);
  }

  // Personal payloads use `user`; org payloads use a folder key of the folder itself (folder items)
  // or of the item's folderId, for the same part.
  static bool _keyIdFits(PayloadAad aad, String keyId) {
    if (aad.scope == ItemScope.personal) return keyId == KeyIds.user;
    final f = KeyIds.parseFolder(keyId);
    final expected = keyFolderIdOf(
      type: aad.type,
      id: aad.itemId,
      folderId: aad.folderId,
    );
    return f != null && f.part == aad.part && f.folderId == expected;
  }
}
