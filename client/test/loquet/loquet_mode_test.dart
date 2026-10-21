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
      expect(
        effectiveLoquetMode(serverFlag: false, org: null, pref: pref),
        LoquetMode.off,
      );
    }
  });

  test('the shown org with mascot false turns it off, any status', () {
    expect(
      effectiveLoquetMode(
        serverFlag: true,
        org: org(settings: {'mascot': false}),
        pref: LoquetMode.on,
      ),
      LoquetMode.off,
    );
    expect(
      effectiveLoquetMode(
        serverFlag: true,
        org: org(status: 'accepted', settings: {'mascot': false}),
        pref: LoquetMode.sober,
      ),
      LoquetMode.off,
    );
  });

  test('the personal vault and a missing org setting keep the user pref', () {
    for (final pref in LoquetMode.values) {
      for (final shown in [
        null,
        org(),
        org(settings: {'future': 1}),
      ]) {
        expect(
          effectiveLoquetMode(serverFlag: true, org: shown, pref: pref),
          pref,
        );
      }
    }
  });

  test('never raises the level', () {
    for (final server in [true, false]) {
      for (final shown in [
        null,
        org(settings: {'mascot': false}),
      ]) {
        for (final pref in LoquetMode.values) {
          expect(
            effectiveLoquetMode(
              serverFlag: server,
              org: shown,
              pref: pref,
            ).index,
            greaterThanOrEqualTo(pref.index),
          );
        }
      }
    }
  });
}
