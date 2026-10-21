// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

final full = {
  'api': [1],
  'minClient': '0.2.0',
  'latestClient': '0.3.0',
  'capabilities': ['mascot', 'sync'],
  'server': '0.3.1',
  'instanceEpoch': 'q83vEjRWeJCrze8SNFZ4kA',
  'source': 'https://example.org/src',
  'trashDays': 30,
};
ApiInfo info([Map<String, Object?> over = const {}]) =>
    ApiInfo.fromJson({...full, ...over});

void main() {
  test('ApiInfo full and public forms round-trip; has()', () {
    expect(jsonEncode(info().toJson()), jsonEncode(full));
    final public = {
      'motd': 'kept',
      'api': [1],
      'minClient': '0.2.0',
      'latestClient': '0.3.0',
      'capabilities': ['sync'],
    };
    final p = ApiInfo.fromJson(public);
    expect(
      (
        p.server,
        p.instanceEpoch,
        p.trashDays,
        p.capabilities.contains('sync'),
        p.has(Flag.mascot),
      ),
      (null, null, null, true, false),
    );
    expect(jsonEncode(p.toJson()), jsonEncode(public));
  });

  test('malformed ApiInfo throws FormatException', () {
    for (final over in [
      {
        'api': ['1'],
      },
      {'minClient': '1.0'},
      {'latestClient': null},
      {'capabilities': 'sync'},
      {'server': '0.3'},
      {'instanceEpoch': 'short'},
      {'instanceEpoch': '${'A' * 21}+'},
      {'trashDays': -1},
      {'source': 7},
    ]) {
      expect(() => info(over), throwsFormatException, reason: '$over');
    }
  });

  test('Flag wire names are pinned', () {
    expect(Flag.values.map((f) => f.wire), [
      'orgs',
      'teams',
      'user_overrides',
      'invites_from_orgs',
      'smtp_invites',
      'security_emails',
      'audit',
      'client_events',
      'item_history',
      'recovery_kit',
      'plain_http_lan',
      'reveal',
      'biometric_unlock',
      'ssh_config_import',
      'mascot',
    ]);
  });

  test('Flag.fromWire reads known names and returns null for others', () {
    expect(Flag.fromWire('recovery_kit'), Flag.recoveryKit);
    expect(Flag.fromWire('telemetry'), isNull);
  });
}
