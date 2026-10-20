// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:typed_data';

import '../bytes.dart';
import '../time.dart';
import '../util/json_reader.dart';
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

  static Future<({DateTime exportedAt, List<Map<String, Object?>> items})> open(
    String text,
    String passphrase, {
    bool allowTestingKdf = false,
  }) async {
    final r = JsonReader(
      jsonDecode(text),
      'export',
    ); // bad JSON or not an object: FormatException
    if (r.req<String>('format') != 'unfeudal-export' || r.req<int>('v') != 1) {
      throw const UnsupportedEnvelope('vault export');
    }
    final kdf = KdfParams.fromJson(r.object('kdf'));
    final salt = unb64(r.req<String>('salt'));
    final data = Envelope.fromJson(r.object('data'));
    if (salt.length != 16) throw const FormatException('export.salt: 16 bytes');
    kdf.ensureAcceptable(
      allowTesting: allowTestingKdf,
    ); // before any derivation
    final key = await hkdf32(await argon2id(passphrase, salt, kdf), _info);
    final Uint8List plain;
    try {
      plain = await SymmetricCipher.decrypt(key, data, aad: _aad);
    } on DecryptionFailed {
      throw const WrongPassword();
    }
    final body = JsonReader(jsonDecode(utf8.decode(plain)), 'export.data');
    return (
      exportedAt: parseIso(body.req<String>('exportedAt')),
      items: [
        for (final i in body.req<List<Object?>>('items'))
          JsonReader(i, 'export.items').map,
      ],
    );
  }

  static String plain(List<Map<String, Object?>> items, {DateTime? now}) =>
      jsonEncode({
        'format': 'unfeudal-export-plain',
        'v': 1,
        'warning': warning,
        ..._body(items, now),
      });
}
