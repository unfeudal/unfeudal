// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/settings/settings.dart';
import 'package:unfeudal_client/src/ui/hosts/host_editor_panel.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('performance mode: panels, tree and seals settle in one frame', (
    t,
  ) async {
    final s = await signedInState(
      t,
      settings: const Settings(performanceMode: true),
    );
    await pumpApp(t, state: s);
    await pumpReal(t, rounds: 5);
    await t.tap(find.byKey(const Key('tree-new-host')));
    await t.pump();
    await t.pump();
    expect(find.byType(HostEditorPanel), findsOneWidget);
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets(
    'the editor grows out of the control that opened it, then settles',
    (t) async {
      final s = await signedInState(t);
      await pumpApp(t, state: s);
      await pumpReal(t, rounds: 5);
      await t.tap(find.byKey(const Key('tree-new-host')));
      await t.pump();
      await t.pump(); // the growth starts once the editor is laid out
      await t.pump(const Duration(milliseconds: 100));
      double opacity() => t
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byType(HostEditorPanel),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      expect(opacity(), inExclusiveRange(0, 1));
      await t.pump(const Duration(milliseconds: 500));
      expect(opacity(), 1);
    },
  );
}
