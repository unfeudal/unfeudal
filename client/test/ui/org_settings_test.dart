// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/ui/orgs/org_settings_screen.dart';
import 'package:unfeudal_client/src/ui/orgs/rotation_banner.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/org_fixtures.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  late SyncHarness h;
  Future<AppState> open(
    WidgetTester t,
    Widget child, {
    String role = 'owner',
    List<Map<String, Object?>> pending = const [],
  }) async {
    h = SyncHarness(capabilities: ['mascot', 'orgs', 'sync']);
    final s = await signedInState(t, harness: h);
    await t.runAsync(() async {
      h.orgBlock = orgBlock(
        role: role,
        members: [memberRow(s.stored!.userId, role: role, status: 'confirmed')],
        pendingRotations: pending,
      );
      await s.sync!.syncNow();
    });
    await pumpApp(t, state: s, child: child);
    return s;
  }

  testWidgets('settings send only what changed; a cleared retention is null', (
    t,
  ) async {
    await open(t, const OrgSettingsScreen(orgId: testOrgId));
    await t.tap(find.byKey(const Key('org-mascot')));
    await t.enterText(find.byKey(const Key('org-audit-days')), '90');
    await t.tap(find.byKey(const Key('org-settings-save')));
    await pumpReal(t);
    expect(h.orgCalls.single.body, {
      'settings': {'mascot': false, 'auditDays': 90},
    });
    await t.enterText(find.byKey(const Key('org-audit-days')), '');
    await t.tap(find.byKey(const Key('org-settings-save')));
    await pumpReal(t);
    expect(h.orgCalls.last.body, {
      'settings': {'auditDays': null},
    });
  });

  testWidgets('delete needs the exact name', (t) async {
    await open(t, const OrgSettingsScreen(orgId: testOrgId));
    await t.tap(find.byKey(const Key('org-delete')));
    await t.pump();
    await t.enterText(find.byKey(const Key('org-delete-confirm')), 'acme');
    expect(
      t.widget<FilledButton>(find.byKey(const Key('org-delete-ok'))).onPressed,
      isNull,
    );
    await t.enterText(find.byKey(const Key('org-delete-confirm')), 'Acme');
    await t.pump();
    await t.tap(find.byKey(const Key('org-delete-ok')));
    await pumpReal(t);
    expect(h.orgCalls.last.route, 'DELETE /orgs/$testOrgId');
  });

  testWidgets('an admin sees no delete', (t) async {
    await open(t, const OrgSettingsScreen(orgId: testOrgId), role: 'admin');
    expect(find.byKey(const Key('org-delete')), findsNothing);
  });

  testWidgets('a member sees no settings, only leaving', (t) async {
    await open(t, const OrgSettingsScreen(orgId: testOrgId), role: 'member');
    expect(find.byKey(const Key('org-settings-save')), findsNothing);
    expect(find.byKey(const Key('org-leave')), findsOneWidget);
  });

  Map<String, Object?> pendingRotation() => {
    'orgId': testOrgId,
    'folderId': newId(),
    'reason': 'member_removed',
    'removedUserIds': [newId()],
    'rotatedVersion': null,
  };

  testWidgets('rotation banner: count, credentials note, rotate now', (
    t,
  ) async {
    final s = await open(
      t,
      const RotationBanner(),
      role: 'admin',
      pending: [pendingRotation()],
    );
    expect(find.text('Keys of 1 folder must change.'), findsOneWidget);
    expect(
      find.textContaining('change those passwords and keys'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('rotation-now')));
    await pumpReal(t);
    expect(s.orgs!.lastRotation, isNotNull);
  });

  testWidgets('a member sees no rotation banner', (t) async {
    await open(
      t,
      const RotationBanner(),
      role: 'member',
      pending: [pendingRotation()],
    );
    expect(find.byKey(const Key('rotation-now')), findsNothing);
  });
}
