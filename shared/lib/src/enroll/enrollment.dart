// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:typed_data';

import '../bytes.dart';
import '../crypto/cipher.dart';
import '../crypto/envelope.dart';
import '../crypto/errors.dart';
import '../crypto/kdf.dart';
import '../net/lan.dart';
import '../util/base32.dart';
import '../util/json_reader.dart';
import '../util/secure.dart';

enum EnrollKind { setup, invite }

String normalizeSetupToken(String t) =>
    t.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

/// RFC 4648 base32 of 16 random bytes, no padding: 26 characters.
String newSetupToken() => base32Encode(secureBytes(16));

/// Groups of 4 joined by `-`, for display; [normalizeSetupToken] reverts it.
String groupSetupToken(String t) => groupBy4(t);

/// A normalized setup token: 26 base32 characters.
bool isSetupToken(String t) => _setupToken.hasMatch(t);

final _setupToken = RegExp(r'^[A-Z2-7]{26}$');

/// A server URL and a setup or invite token, carried by a link or a file.
class Enrollment {
  /// Throws [FormatException] for a non-https server (http only toward a LAN
  /// host) or a malformed token. A setup token is normalised first.
  factory Enrollment(Uri server, String token, EnrollKind kind) {
    final isHttps = server.scheme == 'https';
    final isLanHttp = server.scheme == 'http' && isLanHost(server);
    if (!(isHttps || isLanHttp) ||
        server.host.isEmpty ||
        server.userInfo.isNotEmpty ||
        server.hasQuery ||
        server.hasFragment) {
      throw const FormatException(
        'enroll.server: https, or http on a LAN host',
      );
    }
    final normalized = kind == EnrollKind.setup
        ? normalizeSetupToken(token)
        : token;
    final valid = kind == EnrollKind.setup
        ? isSetupToken(normalized)
        : _inviteToken.hasMatch(normalized);
    if (!valid) {
      throw const FormatException('enroll.token: invalid');
    }
    return Enrollment._(server, normalized, kind);
  }

  Enrollment._(this.server, this.token, this.kind);

  static Enrollment parseLink(String link) {
    final uri = Uri.parse(link);
    if (uri.scheme != 'unfeudal' || uri.host != 'enroll') {
      throw const FormatException('enroll: not an enrollment link');
    }
    final query = uri.queryParameters;
    final server = query['server'];
    final token = query['token'];
    if (server == null || token == null) {
      throw const FormatException('enroll: server and token required');
    }
    return Enrollment(Uri.parse(server), token, _kind(query['kind']));
  }

  static const _info = 'unfeudal/enroll/v1';
  static final _inviteToken = RegExp(r'^[A-Za-z0-9_-]{43}$');

  final Uri server;
  final String token;
  final EnrollKind kind;

  String toLink() => Uri(
    scheme: 'unfeudal',
    host: 'enroll',
    queryParameters: {'server': '$server', 'token': token, 'kind': kind.name},
  ).toString();

  static Future<Enrollment> parseFile(
    String text, {
    String? passphrase,
    bool allowTestingKdf = false,
  }) async {
    // Bad JSON throws FormatException.
    final r = JsonReader(jsonDecode(text), 'enroll');
    if (r.req<int>('unfeudal-enroll') != 1) {
      throw const UnsupportedEnvelope('enrollment file');
    }
    final encrypted = r.opt<Map<String, Object?>>('encrypted');
    if (encrypted == null) return _fromFields(r);
    final e = JsonReader(encrypted, 'enroll.encrypted');
    final salt = e.bytes('salt', length: 16);
    final kdf = KdfParams.fromJson(e.object('kdf'));
    final envelope = Envelope.fromJson(e.object('envelope'));
    // Before any derivation: the file may come from anyone.
    kdf.ensureAcceptable(allowTesting: allowTestingKdf);
    if (passphrase == null) throw const WrongPassword();
    final key = await hkdf32(await argon2id(passphrase, salt, kdf), _info);
    final Uint8List plain;
    try {
      plain = await SymmetricCipher.decrypt(key, envelope);
    } on DecryptionFailed {
      throw const WrongPassword();
    }
    return _fromFields(JsonReader(jsonDecode(utf8.decode(plain)), 'enroll'));
  }

  /// Encrypted: {"unfeudal-enroll": 1, "encrypted": {salt, kdf, envelope}}, keyId `enroll`, no aad,
  /// plaintext {"server", "token", "kind"}.
  Future<String> toFile({
    String? passphrase,
    KdfParams kdf = KdfParams.defaults,
  }) async {
    final fields = {'server': '$server', 'token': token, 'kind': kind.name};
    if (passphrase == null) {
      return jsonEncode({'unfeudal-enroll': 1, ...fields});
    }
    final salt = secureBytes(16);
    final key = await hkdf32(await argon2id(passphrase, salt, kdf), _info);
    final envelope = await SymmetricCipher.encrypt(
      key,
      utf8.encode(jsonEncode(fields)),
      KeyIds.enroll,
    );
    return jsonEncode({
      'unfeudal-enroll': 1,
      'encrypted': {
        'salt': b64(salt),
        'kdf': kdf.toJson(),
        'envelope': envelope.toJson(),
      },
    });
  }

  static Enrollment _fromFields(JsonReader r) => Enrollment(
    Uri.parse(r.text('server', max: 2048)),
    r.text('token', max: 200),
    _kind(r.opt<String>('kind')),
  );

  /// Absent means setup.
  static EnrollKind _kind(String? name) => name == null
      ? EnrollKind.setup
      : EnrollKind.values.asNameMap()[name] ??
            (throw const FormatException('enroll.kind: unknown'));
}
