// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/config/features.dart';

void main() {
  test('fifteen flags with their wire names; all on except plain_http_lan', () {
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
    final f = Features(const {});
    expect(Flag.values.where((x) => !f.enabled(x)), [Flag.plainHttpLan]);
    expect(Flag.fromWire('recovery_kit'), Flag.recoveryKit);
    expect(Flag.fromWire('telemetry'), isNull);
  });

  test('capabilities: sync plus enabled flags, sorted; public form only three flags', () {
    final f = Features(const {
      Flag.mascot: false,
      Flag.plainHttpLan: true,
      Flag.audit: false,
    });
    expect(f.publicCapabilities(), ['plain_http_lan', 'recovery_kit', 'sync']);
    final all = f.capabilities();
    expect(all, [...all]..sort());
    expect(all, containsAll(['sync', 'plain_http_lan', 'orgs']));
    expect(all, isNot(contains('mascot')));
    expect(all, isNot(contains('audit')));
    expect(
      Features(const {Flag.recoveryKit: false, Flag.mascot: false})
          .publicCapabilities(),
      ['sync'],
    );
  });
}
