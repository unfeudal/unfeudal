// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/config/features.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  test('all flags on by default except plain_http_lan', () {
    final f = Features(const {});
    expect(Flag.values.where((x) => !f.enabled(x)), [Flag.plainHttpLan]);
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
