// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/ui/orgs/org_settings_screen.dart';

import '../support/org_fixtures.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  testWidgets(
    'fields show the org values and the server values from the route; clearing sends null',
    (t) async {
      final h = SyncHarness(capabilities: ['mascot', 'orgs', 'sync']);
      final s = await signedInState(t, harness: h);
      await t.runAsync(() async {
        h.orgBlock = orgBlock(
          role: 'owner',
          members: [
            memberRow(s.stored!.userId, role: 'owner', status: 'confirmed'),
          ],
        );
        await s.sync!.syncNow();
      });
      h.retention[testOrgId] = {
        'server': {'auditDays': 365, 'maxVersions': 0, 'trashDays': 30},
        'org': {'auditDays': 90, 'maxVersions': null, 'trashDays': null},
      };
      await pumpApp(
        t,
        state: s,
        child: const OrgSettingsScreen(orgId: testOrgId),
      );
      await pumpReal(t);
      expect(
        find.descendant(
          of: find.byKey(const Key('org-audit-days')),
          matching: find.text('90'),
        ),
        findsOneWidget,
      );
      expect([
        find.text('Server: 365'),
        find.text('Server: unlimited'),
        find.text('Server: 30'),
      ], everyElement(findsOneWidget));
      await t.enterText(find.byKey(const Key('org-audit-days')), '');
      await t.tap(find.byKey(const Key('org-settings-save')));
      await pumpReal(t);
      expect(h.orgCalls.last.body, {
        'settings': {'auditDays': null},
      });
      await t.enterText(find.byKey(const Key('org-audit-days')), '60');
      await t.tap(find.byKey(const Key('org-settings-save')));
      await pumpReal(t);
      await t.enterText(find.byKey(const Key('org-audit-days')), '');
      await t.tap(find.byKey(const Key('org-settings-save')));
      await pumpReal(t);
      expect(
        [for (final c in h.orgCalls.skip(h.orgCalls.length - 2)) c.body],
        [
          {
            'settings': {'auditDays': 60},
          },
          {
            'settings': {'auditDays': null},
          },
        ],
        reason: 'a save becomes the new baseline',
      );
    },
  );
}
