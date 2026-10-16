// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../util/clock.dart';
import 'secret_hash.dart';

List<int> _hmac(List<int> key, String msg) =>
    Hmac(sha256, key).convert(utf8.encode(msg)).bytes;

class AccessClaims {
  const AccessClaims(this.userId, this.deviceId, this.exp);

  final String userId;
  final String deviceId;
  final DateTime exp;
}

/// `b64(json{u, d, exp ms}) . b64(HMAC-SHA256(server_secret, "access:" + payload))`.
class AccessTokens {
  AccessTokens(this._secret, this._clock, this.ttl);

  final List<int> _secret;
  final Clock _clock;
  final Duration ttl;

  String issue(String userId, String deviceId) {
    final exp = _clock.now().add(ttl).millisecondsSinceEpoch;
    final payload = b64(
      utf8.encode(jsonEncode({'u': userId, 'd': deviceId, 'exp': exp})),
    );
    return '$payload.${b64(_hmac(_secret, 'access:$payload'))}';
  }

  /// One dot, constant-time MAC, valid JSON, now < exp; anything else → null.
  AccessClaims? verify(String token) {
    final parts = token.split('.');
    if (parts.length != 2) return null;
    try {
      if (!constantTimeEquals(
        _hmac(_secret, 'access:${parts[0]}'),
        unb64(parts[1]),
      )) {
        return null;
      }
      final json = jsonDecode(utf8.decode(unb64(parts[0])));
      if (json is! Map<String, Object?>) return null;
      final (u, d, exp) = (json['u'], json['d'], json['exp']);
      if (u is! String ||
          d is! String ||
          exp is! int ||
          !isUuid(u) ||
          !isUuid(d)) {
        return null;
      }
      if (_clock.now().millisecondsSinceEpoch >= exp) return null;
      return AccessClaims(
        u,
        d,
        DateTime.fromMillisecondsSinceEpoch(exp, isUtc: true),
      );
    } on FormatException {
      return null;
    }
  }
}

/// Stored form of refresh, setup and invite tokens.
String hashToken(String token) => b64(sha256.convert(utf8.encode(token)).bytes);

String refreshSuccessor(List<int> secret, String token) =>
    b64(_hmac(secret, 'refresh-next:$token'));

/// Stable per email, so prelogin cannot tell an unknown email from a known one.
Uint8List preloginFakeSalt(List<int> secret, String email) =>
    Uint8List.fromList(_hmac(secret, 'prelogin-salt:$email').sublist(0, 16));
