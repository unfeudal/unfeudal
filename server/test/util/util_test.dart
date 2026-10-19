// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/util/random.dart';
import 'package:unfeudal_server/src/version.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fake_clock.dart';

void main() {
  test(
    'server constants are X.Y.Z and the default min_client_version fits',
    () {
      expect(Version.parse(serverVersion).toString(), serverVersion);
      expect(
        compareVersions('0.1.0', latestClientVersion),
        lessThanOrEqualTo(0),
      );
    },
  );

  test('randomToken is base64url of 32 fresh bytes', () {
    final t = randomToken();
    expect(t, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(unb64(t), hasLength(32));
    expect(randomToken(), isNot(t));
    expect(secureBytes(16), hasLength(16));
  });

  test('newSetupToken is 26 base32 chars; grouped form normalises back', () {
    final s = newSetupToken();
    expect(s, matches(RegExp(r'^[A-Z2-7]{26}$')));
    expect(
      groupSetupToken(s),
      matches(RegExp(r'^([A-Z2-7]{4}-){6}[A-Z2-7]{2}$')),
    );
    expect(normalizeSetupToken(groupSetupToken(s)), s);
  });

  test('FakeClock advances without waiting', () {
    final c = FakeClock(DateTime.utc(2026, 10, 13, 12));
    c.advance(const Duration(minutes: 1));
    expect(c.now(), DateTime.utc(2026, 10, 13, 12, 1));
  });
}
