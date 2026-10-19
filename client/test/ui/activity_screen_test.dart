// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/ui/activity/activity_screen.dart';
import 'package:unfeudal_client/src/ui/shell/home_shell.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/org_fixtures.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  testWidgets(
    'rows, load more, verify, export, raw IPs for the Instance Owner, the SSH note',
    (t) async {
      final h = SyncHarness(capabilities: ['audit', 'mascot', 'sync']);
      final s = await signedInState(
        t,
        harness: h,
      ); // the first account is the Instance Owner
      final me = s.stored!.userId;
      for (var i = 0; i < 101; i++) {
        h.appendAudit(
          'user:$me',
          'device.added',
          actorUser: me,
          ipAddress: '203.0.113.7',
        );
      }
      final saved = <String, List<int>>{};
      await pumpApp(
        t,
        state: s,
        child: ActivityScreen(
          savePath: (name) async => '/tmp/$name',
          writeFile: (path, bytes) async => saved[path] = bytes,
        ),
      );
      await pumpReal(t);
      expect(find.text('A device signed in'), findsWidgets);
      expect(find.text('203.0.113.7'), findsWidgets);
      await t.tap(find.byKey(const Key('activity-more')));
      await pumpReal(t);
      expect(find.byKey(const Key('activity-more')), findsNothing);
      await t.tap(find.byKey(const Key('activity-verify')));
      await pumpReal(t);
      expect(find.text('Chain verified: 101 events.'), findsOneWidget);
      await t.tap(find.byKey(const Key('activity-export')));
      await pumpReal(t);
      expect(saved.keys, ['/tmp/unfeudal-audit-user.json']);
      expect(find.textContaining('reported by the app'), findsOneWidget);
    },
  );

  testWidgets(
    'scopes: org for admins, folders with manage, instance for the Instance Owner',
    (t) async {
      final h = SyncHarness(capabilities: ['audit', 'orgs', 'sync']);
      final s = await signedInState(t, harness: h);
      final me = s.stored!.userId;
      final (f, g) = (newId(), newId());
      await t.runAsync(() async {
        h.orgBlock = orgBlock(
          role: 'member',
          members: [memberRow(me, status: 'confirmed')],
          folderTree: [node(f), node(g)],
          acl: [
            aclRow(f, me, allow: ['manage']),
            aclRow(g, me, allow: ['view']),
          ],
        );
        await s.sync!.syncNow();
      });
      await pumpApp(t, state: s, child: const ActivityScreen());
      await pumpReal(t);
      await t.tap(find.byKey(const Key('activity-scope')));
      await t.pumpAndSettle();
      for (final scope in ['me', 'user', 'instance', 'folder:$f']) {
        expect(
          find.byKey(Key('activity-scope-$scope')),
          findsWidgets,
          reason: scope,
        );
      }
      expect(find.byKey(Key('activity-scope-folder:$g')), findsNothing);
      expect(
        find.byKey(const Key('activity-scope-org:$testOrgId')),
        findsNothing,
        reason: 'members do not read the org chain',
      );
      await t.tap(find.byKey(Key('activity-scope-folder:$f')).last);
      await pumpReal(t);
      expect([
        find.byKey(const Key('activity-verify')),
        find.byKey(const Key('activity-export')),
      ], everyElement(findsNothing));
    },
  );

  testWidgets('a rewritten chain shows a danger banner', (t) async {
    final h = SyncHarness(capabilities: ['audit', 'sync']);
    final s = await signedInState(t, harness: h);
    final me = s.stored!.userId;
    for (var i = 0; i < 3; i++) {
      h.appendAudit('user:$me', 'device.added', actorUser: me);
    }
    await pumpApp(
      t,
      state: s,
      child: const ActivityScreen(scope: 'user'),
    );
    await pumpReal(t);
    h.rewriteAudit('user:$me', 2, 'item.created');
    await pumpApp(
      t,
      state: s,
      child: const ActivityScreen(key: ValueKey(2), scope: 'user'),
    );
    await pumpReal(t);
    expect(find.byKey(const Key('activity-alert')), findsOneWidget);
  });

  testWidgets(
    'export verifies the chain and still saves a broken one, with a warning',
    (t) async {
      final h = SyncHarness(capabilities: ['audit', 'sync']);
      final s = await signedInState(t, harness: h);
      final me = s.stored!.userId;
      for (var i = 0; i < 3; i++) {
        h.appendAudit('user:$me', 'device.added', actorUser: me);
      }
      final i = h.auditLog.indexWhere(
        (e) => e.scope == 'user:$me' && e.seq == 2,
      );
      h.auditLog[i] = AuditEvent.fromJson({
        ...h.auditLog[i].toJson(),
        'action': 'item.created',
      }); // hash left as it was
      final saved = <String>[];
      await pumpApp(
        t,
        state: s,
        child: ActivityScreen(
          scope: 'user',
          savePath: (name) async => '/tmp/$name',
          writeFile: (path, bytes) async => saved.add(path),
        ),
      );
      await pumpReal(t);
      await t.tap(find.byKey(const Key('activity-export')));
      await pumpReal(t);
      expect(saved, hasLength(1));
      expect(find.textContaining('breaks at event'), findsOneWidget);
    },
  );

  testWidgets(
    'the Instance Owner opens a deleted org\'s chain from its deletion event',
    (t) async {
      final h = SyncHarness(capabilities: ['audit', 'sync']);
      final s = await signedInState(
        t,
        harness: h,
      ); // the first account is the Instance Owner
      final gone = newId();
      h.appendAudit('org:$gone', 'org.created', actorUser: s.stored!.userId);
      h.appendAudit(
        'instance',
        'org.deleted',
        actorUser: s.stored!.userId,
        targets: [gone],
      );
      await pumpApp(
        t,
        state: s,
        child: const ActivityScreen(scope: 'instance'),
      );
      await pumpReal(t);
      await t.tap(find.byKey(Key('activity-open-org-$gone')));
      await pumpReal(t);
      expect(h.requests.where((r) => r == 'GET /api/v1/audit'), hasLength(2));
      expect(find.byKey(Key('activity-scope-org:$gone')), findsWidgets);
    },
  );

  testWidgets('the rail shows Activity only when the server has audit', (
    t,
  ) async {
    for (final (caps, shown) in [
      (['audit', 'sync'], true),
      (['sync'], false),
    ]) {
      final s = await signedInState(
        t,
        harness: SyncHarness(capabilities: caps),
      );
      await pumpApp(t, state: s, child: const HomeShell());
      await pumpReal(t);
      expect(
        find.byKey(const Key('rail-activity')),
        shown ? findsOneWidget : findsNothing,
      );
    }
  });
}
