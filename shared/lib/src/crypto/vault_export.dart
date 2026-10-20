// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import '../bytes.dart';
import '../time.dart';
import '../util/secure.dart';
import 'cipher.dart';
import 'envelope.dart';
import 'errors.dart';
import 'kdf.dart';

/// The vault export file: sealed with a passphrase (at least [minPassphraseLength] code points), or plaintext.
class VaultExport {
  static const minPassphraseLength = 12;
  static const _info = 'unfeudal/export/v1';
  static final _aad = utf8.encode('unfeudal-export/v1');
  static const warning =
      'This file is not encrypted: anyone who reads it gets every secret in it.';

  static Map<String, Object?> _body(
    List<Map<String, Object?>> items,
    DateTime? now,
  ) => {'exportedAt': iso(now ?? DateTime.now().toUtc()), 'items': items};

  static Future<String> seal(
    List<Map<String, Object?>> items,
    String passphrase, {
    KdfParams kdf = KdfParams.defaults,
    DateTime? now,
  }) async {
    if (passwordLength(passphrase) < minPassphraseLength) {
      throw const WeakPassword();
    }
    final salt = secureBytes(16);
    final key = await hkdf32(await argon2id(passphrase, salt, kdf), _info);
    final data = await SymmetricCipher.encrypt(
      key,
      utf8.encode(jsonEncode(_body(items, now))),
      KeyIds.export,
      aad: _aad,
    );
    return jsonEncode({
      'format': 'unfeudal-export',
      'v': 1,
      'kdf': kdf.toJson(),
      'salt': b64(salt),
      'data': data.toJson(),
    });
  }

  static String plain(List<Map<String, Object?>> items, {DateTime? now}) =>
      jsonEncode({
        'format': 'unfeudal-export-plain',
        'v': 1,
        'warning': warning,
        ..._body(items, now),
      });
}
