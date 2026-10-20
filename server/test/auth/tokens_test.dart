// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:unfeudal_server/src/auth/tokens.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fake_clock.dart';

const u = '5d1e9a7c-2b3f-4c8d-9e0a-1b2c3d4e5f60';
const d = '8c7b6a59-4e3d-4c2b-a190-8f7e6d5c4b3a';

void main() {
  final secret = List.filled(32, 9);
  final clock = FakeClock(DateTime.utc(2026, 10, 13, 12));
  final access = AccessTokens(secret, clock, const Duration(minutes: 15));

  test('access token is payload.mac and verifies until exp', () {
    final t = access.issue(u, d);
    final [payload, mac] = t.split('.');
    expect(jsonDecode(utf8.decode(unb64(payload))), {
      'u': u,
      'd': d,
      'exp': DateTime.utc(2026, 10, 13, 12, 15).millisecondsSinceEpoch,
    });
    expect(
      unb64(mac),
      Hmac(sha256, secret).convert(utf8.encode('access:$payload')).bytes,
    );
    final c = access.verify(t)!;
    expect((c.userId, c.deviceId), (u, d));
  });

  test('a forged, re-signed, malformed or expired access token is refused', () {
    final t = access.issue(u, d);
    final [payload, mac] = t.split('.');
    final other = AccessTokens(
      List.filled(32, 1),
      clock,
      const Duration(minutes: 15),
    ).issue(u, d);
    final forged = b64(
      utf8.encode(jsonEncode({'u': u, 'd': d, 'exp': 1 << 50})),
    );
    for (final bad in [
      other,
      '$forged.$mac',
      '$payload.${mac}x',
      '$payload.',
      t.replaceFirst('.', ''),
      '$t.x',
      'a.b',
      '',
    ]) {
      expect(access.verify(bad), isNull, reason: bad);
    }
    final notJson = b64(utf8.encode('nope'));
    expect(
      access.verify(
        '$notJson.${b64(Hmac(sha256, secret).convert(utf8.encode('access:$notJson')).bytes)}',
      ),
      isNull,
    );
    clock.advance(const Duration(minutes: 15));
    expect(access.verify(t), isNull, reason: 'now == exp is expired');
  });

  test('hashToken, successor and prelogin fake salt are pinned', () {
    expect(hashToken('abc'), b64(sha256.convert(utf8.encode('abc')).bytes));
    expect(
      refreshSuccessor(secret, 'tok'),
      b64(Hmac(sha256, secret).convert(utf8.encode('refresh-next:tok')).bytes),
    );
    final salt = preloginFakeSalt(secret, 'a@b.c');
    expect(
      salt,
      Hmac(
        sha256,
        secret,
      ).convert(utf8.encode('prelogin-salt:a@b.c')).bytes.sublist(0, 16),
    );
    expect(preloginFakeSalt(secret, 'a@b.c'), salt);
    expect(preloginFakeSalt(secret, 'x@b.c'), isNot(salt));
  });
}
