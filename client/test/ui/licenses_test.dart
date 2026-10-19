// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/ui/settings/licenses_screen.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets(
    'font licences registered; the server source shown; the full list opens',
    (t) async {
      registerFontLicenses();
      final packages = await t.runAsync(
        () async => [
          await for (final l in LicenseRegistry.licenses) ...l.packages,
        ],
      );
      expect(
        packages,
        containsAll(['Alegreya', 'Hanken Grotesk', 'JetBrains Mono']),
      );
      final s = await signedInState(t);
      await t.runAsync(() => s.sync!.syncNow());
      await pumpApp(t, state: s, child: const LicensesScreen());
      await pumpReal(t, rounds: 5);
      expect(
        find.text('https://example.org/src'),
        findsOneWidget,
      ); // the harness's /api/info.source
      await t.tap(find.byKey(const Key('licenses-all')));
      await pumpReal(
        t,
        rounds: 5,
      ); // pumpAndSettle times out on the licence page
      expect(find.byType(LicensePage), findsOneWidget);
    },
  );
}
