// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/loquet/loquet_mode.dart';
import 'package:unfeudal_client/src/settings/settings.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

OrgSummary org({
  String status = 'confirmed',
  Map<String, Object?> settings = const {},
}) => OrgSummary.fromJson({
  'id': newId(),
  'name': 'Acme',
  'role': 'member',
  'status': status,
  'settings': settings,
});

void main() {
  test('server flag off beats every pref', () {
    for (final pref in LoquetMode.values) {
      expect(effectiveLoquetMode(false, const [], pref), LoquetMode.off);
    }
  });

  test('one org with mascot false turns it off, any status', () {
    final orgs = [
      org(),
      org(status: 'accepted', settings: {'mascot': false}),
      org(settings: {'mascot': true}),
    ];
    expect(effectiveLoquetMode(true, orgs, LoquetMode.on), LoquetMode.off);
    expect(
      effectiveLoquetMode(true, [
        org(status: 'accepted', settings: {'mascot': false}),
      ], LoquetMode.sober),
      LoquetMode.off,
    );
  });

  test('a missing org setting means on; the user pref passes through', () {
    final orgs = [
      org(),
      org(settings: {'future': 1}),
    ];
    for (final pref in LoquetMode.values) {
      expect(effectiveLoquetMode(true, orgs, pref), pref);
      expect(effectiveLoquetMode(true, const [], pref), pref);
    }
  });

  test('never raises the level', () {
    for (final server in [true, false]) {
      for (final orgs in [
        <OrgSummary>[],
        [
          org(settings: {'mascot': false}),
        ],
      ]) {
        for (final pref in LoquetMode.values) {
          expect(
            effectiveLoquetMode(server, orgs, pref).index,
            greaterThanOrEqualTo(pref.index),
          );
        }
      }
    }
  });
}
