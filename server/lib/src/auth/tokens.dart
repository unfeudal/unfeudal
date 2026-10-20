// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/helpers.dart' show constantTimeBytesEquality;
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../api/errors.dart';
import '../api/session.dart';
import '../audit/audit_log.dart';
import '../db/db.dart';
import '../util/clock.dart';

List<int> _hmac(List<int> key, String msg) =>
    Hmac(sha256, key).convert(utf8.encode(msg)).bytes;

typedef AccessClaims = ({String userId, String deviceId});

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

  /// One dot, constant-time MAC, valid JSON, now before exp; anything else returns null.
  AccessClaims? verify(String token) {
    final parts = token.split('.');
    if (parts.length != 2) return null;
    try {
      if (!constantTimeBytesEquality.equals(
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
      return (userId: u, deviceId: d);
    } on FormatException {
      return null;
    }
  }

  /// [verify] on an `Authorization: Bearer <token>` header; anything else returns null.
  AccessClaims? verifyHeader(String? header) =>
      header != null && header.startsWith('Bearer ')
      ? verify(header.substring(7))
      : null;
}

/// 32 random bytes in base64url (43 characters).
String randomToken() => b64(secureBytes(32));

/// Stored form of refresh, setup and invite tokens.
String hashToken(String token) => b64(sha256.convert(utf8.encode(token)).bytes);

String refreshSuccessor(List<int> secret, String token) =>
    b64(_hmac(secret, 'refresh-next:$token'));

/// Stable per email, so prelogin cannot tell an unknown email from a known one.
Uint8List preloginFakeSalt(List<int> secret, String email) =>
    Uint8List.fromList(_hmac(secret, 'prelogin-salt:$email').sublist(0, 16));

/// Revokes a device (once) and marks every one of its refresh tokens used.
Future<void> revokeDevice(Tx tx, String deviceId, DateTime now) async {
  await tx.execute(
    'UPDATE devices SET revoked_at = @now WHERE id = @d AND revoked_at IS NULL',
    {'now': iso(now), 'd': deviceId},
  );
  await tx.execute(
    'UPDATE refresh_tokens SET used_at = @now WHERE device_id = @d AND used_at IS NULL',
    {'now': iso(now), 'd': deviceId},
  );
}

typedef Rotated = ({String userId, String deviceId, String refreshToken});

class RefreshTokens {
  RefreshTokens(
    this.db,
    this.clock,
    this.ttl,
    this._secret, {
    required this.audit,
  });

  final Db db;
  final Clock clock;
  final Duration ttl;
  final List<int> _secret;

  /// Records a replay in the revocation's transaction.
  final AuditLog audit;

  /// A lost response is answered again with the same successor within this window.
  static const grace = Duration(seconds: 30);

  Future<String> create(Tx tx, String deviceId) async {
    final token = randomToken();
    await _insert(tx, token, deviceId);
    return token;
  }

  Future<void> _insert(Tx tx, String token, String deviceId) => tx.execute(
    'INSERT INTO refresh_tokens (token_hash, device_id, expires_at) VALUES (@h, @d, @e)',
    {'h': hashToken(token), 'd': deviceId, 'e': iso(clock.now().add(ttl))},
  );

  /// One transaction. Failures are returned, then thrown after commit, so a
  /// replay's revocation is never rolled back.
  Future<Rotated> rotate(String token, {String? ip}) async {
    final outcome = await db.transaction<Object>((tx) async {
      final now = clock.now();
      final next = refreshSuccessor(_secret, token);
      while (true) {
        final rows = await tx.query(
          'SELECT r.device_id, r.expires_at, r.used_at, d.user_id, d.revoked_at, u.disabled '
          'FROM refresh_tokens r JOIN devices d ON d.id = r.device_id '
          'JOIN users u ON u.id = d.user_id WHERE r.token_hash = @h',
          {'h': hashToken(token)},
        );
        if (rows.isEmpty) return UnauthorizedReason.invalidToken;
        final row = rows.single;
        final deviceId = row['device_id']! as String;
        final userId = row['user_id']! as String;
        final live = row['revoked_at'] == null && row['disabled'] == 0;
        final usedAt = row['used_at'] as String?;
        if (usedAt != null) {
          final successor = await tx.query(
            'SELECT used_at FROM refresh_tokens WHERE token_hash = @h',
            {'h': hashToken(next)},
          );
          final lostResponse =
              now.difference(parseIso(usedAt)) <= grace &&
              successor.length == 1 &&
              successor.single['used_at'] == null;
          if (lostResponse && live) {
            return (userId: userId, deviceId: deviceId, refreshToken: next);
          }
          // Replay: revoked and committed, then 401.
          await revokeDevice(tx, deviceId, now);
          // no actor: whoever presented the token is unknown
          await audit.append(
            tx,
            scope: AuditScope.user(userId),
            action: 'auth.refresh_replay',
            ip: ip,
            targetIds: [deviceId],
          );
          return UnauthorizedReason.deviceRevoked;
        }
        if (!live) return UnauthorizedReason.deviceRevoked;
        if (!parseIso(row['expires_at']! as String).isAfter(now)) {
          return UnauthorizedReason.sessionExpired;
        }
        final claimed = await tx.execute(
          'UPDATE refresh_tokens SET used_at = @now WHERE token_hash = @h AND used_at IS NULL',
          {'now': iso(now), 'h': hashToken(token)},
        );
        // A concurrent rotation won: re-read, the grace branch answers.
        if (claimed == 0) continue;
        await _insert(tx, next, deviceId);
        await touchDevice(tx, deviceId, now);
        return (userId: userId, deviceId: deviceId, refreshToken: next);
      }
    });
    if (outcome is UnauthorizedReason) {
      throw ApiError(
        ApiErrorCode.unauthorized,
        'Session is no longer valid.',
        extra: {'reason': outcome.wire},
      );
    }
    return outcome as Rotated;
  }
}
