// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/design/acl_grid.dart';
import 'package:unfeudal_client/src/ui/orgs/acl_editor.dart';
import 'package:unfeudal_client/src/ui/orgs/teams_screen.dart';
import 'package:unfeudal_client/src/ui/orgs/why_rights_view.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/org_fixtures.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  final f = newId(), g = newId(), ops = newId(), kim = newId();
  late SyncHarness h;

  Future<AppState> open(
    WidgetTester t,
    Widget Function(String me) child, {
    String role = 'member',
    List<String> caps = const ['teams', 'user_overrides'],
  }) async {
    h = SyncHarness(capabilities: ['mascot', 'orgs', 'sync', ...caps]);
    final s = await signedInState(t, harness: h);
    final me = s.stored!.userId;
    await t.runAsync(() async {
      h.orgBlock = orgBlock(
        role: role,
        members: [
          memberRow(
            me,
            role: role,
            status: role == 'member' ? null : 'confirmed',
          ),
          memberRow(kim, email: 'kim@example.org'),
        ],
        teams: [
          {
            'orgId': testOrgId,
            'id': ops,
            'name': 'Ops',
            'memberIds': [me],
          },
        ],
        folderTree: [node(f), node(g, f)],
        acl: [
          aclRow(f, ops, type: 'team', allow: ['view', 'connect']),
          aclRow(f, me, allow: ['manage']),
          aclRow(g, me, deny: ['connect']),
        ],
      );
      await s.sync!.syncNow();
    });
    await pumpApp(t, state: s, child: child(me));
    return s;
  }

  testWidgets(
    'a manager cannot grant what they lack nor drop their own manage',
    (t) async {
      final s = await open(t, (_) => AclEditor(orgId: testOrgId, folderId: f));
      final me = s.stored!.userId;
      UfTriToggle toggle(String id, String right) =>
          t.widget<UfTriToggle>(find.byKey(Key('acl-$id-$right')));
      await t.tap(find.byKey(Key('acl-$kim-reveal')));
      await t.pump();
      expect(
        toggle(kim, 'reveal').state,
        UfTriState.deny,
        reason: 'caller lacks reveal: it can only be denied',
      );
      await t.tap(find.byKey(Key('acl-$kim-connect')));
      await t.pump();
      expect(toggle(kim, 'connect').state, UfTriState.allow);
      expect(
        toggle(me, 'manage').onChanged,
        isNull,
        reason: 'own manage stays',
      );
      expect(
        find.text(
          'Anyone who can connect holds the secret on their device: Reveal only hides the button.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('teams never get deny; save sends every entry', (t) async {
    await open(
      t,
      (_) => AclEditor(orgId: testOrgId, folderId: f),
      role: 'admin',
    );
    expect(
      t.widget<UfTriToggle>(find.byKey(Key('acl-$ops-view'))).canDeny,
      isFalse,
    );
    await t.tap(find.byKey(Key('acl-$ops-edit')));
    await t.tap(find.byKey(const Key('acl-save')));
    await pumpReal(t);
    final body = h.orgCalls.single;
    expect(body.route, 'PUT /folders/$f/acl');
    final team = (body.body['entries']! as List)
        .cast<Map<String, Object?>>()
        .singleWhere((e) => e['principalId'] == ops);
    expect((team['allow']! as List).toSet(), {'view', 'connect', 'edit'});
  });

  testWidgets('user entries are hidden when user_overrides is off', (t) async {
    await open(
      t,
      (_) => AclEditor(orgId: testOrgId, folderId: f),
      role: 'admin',
      caps: const ['teams'],
    );
    expect(find.byKey(Key('acl-$ops-view')), findsOneWidget);
    expect(find.byKey(Key('acl-$kim-view')), findsNothing);
  });

  testWidgets('teams screen is hidden when teams is off', (t) async {
    await open(
      t,
      (_) => const TeamsScreen(orgId: testOrgId),
      role: 'admin',
      caps: const [],
    );
    expect(find.byKey(const Key('team-new')), findsNothing);
  });

  testWidgets('why view lists the steps of the resolution', (t) async {
    await open(
      t,
      (me) => WhyRightsView(orgId: testOrgId, folderId: g, userId: me),
    );
    expect(
      find.textContaining('Ops on '),
      findsOneWidget,
      reason: 'team entry inherited from the parent',
    );
    expect(
      find.text('Refused for this member: Connect'),
      findsOneWidget,
      reason: 'the child user entry replaces the parent one',
    );
    expect(find.text('Result: View'), findsOneWidget);
  });

  testWidgets('teams: create with members', (t) async {
    await open(t, (_) => const TeamsScreen(orgId: testOrgId), role: 'admin');
    h.orgReplies['POST /orgs/$testOrgId/teams'] = (b) => SyncHarness.reply({
      'team': {'id': newId(), ...b},
    }, 201);
    await t.tap(find.byKey(const Key('team-new')));
    await t.pump();
    await t.enterText(find.byKey(const Key('team-name')), 'Dev');
    await t.tap(find.byKey(Key('team-member-$kim')));
    await t.tap(find.byKey(const Key('team-save')));
    await pumpReal(t);
    expect(h.orgCalls.last.body, {
      'name': 'Dev',
      'memberIds': [kim],
    });
  });
}
