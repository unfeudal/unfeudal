// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/orgs/member_pins.dart';
import 'package:unfeudal_client/src/ui/orgs/invite_dialog.dart';
import 'package:unfeudal_client/src/ui/orgs/members_screen.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/org_fixtures.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  late SyncHarness h;
  final ana = newId(), mia = newId();
  late List<int> anaKey, miaKey;

  Future<AppState> admin(WidgetTester t, {String role = 'admin'}) async {
    h = SyncHarness(
      capabilities: ['mascot', 'orgs', 'sync', 'teams', 'user_overrides'],
    );
    final s = await signedInState(t, harness: h);
    await t.runAsync(() async {
      anaKey = (await memberKeys()).publicKey;
      miaKey = (await memberKeys()).publicKey;
      final me = s.stored!.userId;
      h.orgBlock = orgBlock(
        role: role,
        members: [
          memberRow(
            me,
            role: role,
            status: 'confirmed',
            publicKey: h.accounts.values.first.bundle.publicKey,
          ),
          memberRow(
            ana,
            status: 'accepted',
            publicKey: anaKey,
            email: 'ana@example.org',
          ),
          memberRow(
            mia,
            role: 'admin',
            status: 'confirmed',
            publicKey: miaKey,
            email: 'mia@example.org',
          ),
        ],
      );
      await s.sync!.syncNow();
    });
    await pumpApp(
      t,
      state: s,
      child: const MembersScreen(orgId: testOrgId),
    );
    return s;
  }

  testWidgets(
    'confirm shows the safety code; ticked compared pins verified, then confirms',
    (t) async {
      final s = await admin(t);
      expect(find.text('Awaiting confirmation'), findsOneWidget);
      await t.tap(find.byKey(Key('member-confirm-$ana')));
      await t.pump();
      expect(find.text(safetyCode(anaKey)), findsOneWidget);
      await t.tap(find.byKey(const Key('safety-compared')));
      await t.tap(find.byKey(const Key('safety-match')));
      await pumpReal(t);
      expect(s.orgs!.pins.pinOf(ana)!.verified, isTrue);
      expect(
        h.orgCalls.last.route,
        'POST /orgs/$testOrgId/members/$ana/confirm',
      );
    },
  );

  testWidgets(
    'confirm without ticking pins "not compared"; a confirmed member unknown here asks to be confirmed',
    (t) async {
      final s = await admin(t);
      expect(
        find.text('Confirm on this device to share keys'),
        findsOneWidget,
        reason: 'mia: confirmed, not pinned here',
      );
      await t.tap(find.byKey(Key('member-confirm-$ana')));
      await t.pump();
      await t.tap(find.byKey(const Key('safety-match')));
      await pumpReal(t);
      expect(s.orgs!.pins.pinOf(ana)!.verified, isFalse);
      expect(find.text('Key not compared'), findsOneWidget);
      await t.tap(find.byKey(Key('member-verify-$mia')));
      await t.pump();
      await t.tap(find.byKey(const Key('safety-match')));
      await pumpReal(t);
      expect(s.orgs!.pins.check(mia, miaKey), PinCheck.matches);
    },
  );

  testWidgets('codes that differ confirm nothing and pin nothing', (t) async {
    final s = await admin(t);
    await t.tap(find.byKey(Key('member-confirm-$ana')));
    await t.pump();
    await t.tap(find.byKey(const Key('safety-no-match')));
    await pumpReal(t);
    expect(s.orgs!.pins.pinOf(ana), null);
    expect(h.orgCalls, isEmpty);
  });

  testWidgets('an admin cannot pick admin or owner, nor touch another admin', (
    t,
  ) async {
    await admin(t);
    expect(
      t
          .widget<DropdownButton<OrgRole>>(find.byKey(Key('member-role-$mia')))
          .onChanged,
      isNull,
    );
    await t.tap(find.byKey(Key('member-role-$ana')));
    await t.pumpAndSettle();
    final owner = t.widget<DropdownMenuItem<OrgRole>>(
      find.byKey(const Key('role-option-owner')).last,
    );
    expect(owner.enabled, isFalse);
  });

  testWidgets(
    'a changed key shows an alert; verifying the new code re-pins it',
    (t) async {
      final s = await admin(t);
      await t.runAsync(
        () async => s.orgs!.pins.pin(
          mia,
          (await memberKeys()).publicKey,
          verified: true,
        ),
      );
      await t.pump();
      expect(find.byKey(Key('member-key-changed-$mia')), findsOneWidget);
      await t.tap(find.byKey(Key('member-verify-$mia')));
      await t.pump();
      await t.tap(find.byKey(const Key('safety-compared')));
      await t.tap(find.byKey(const Key('safety-match')));
      await pumpReal(t);
      expect(s.orgs!.pins.check(mia, miaKey), PinCheck.matches);
      expect(s.orgs!.pins.pinOf(mia)!.verified, isTrue);
    },
  );

  testWidgets('remove shows the last-owner refusal; leave asks first', (
    t,
  ) async {
    await admin(t, role: 'owner');
    h.orgReplies['DELETE /orgs/$testOrgId/members/$mia'] = (_) =>
        SyncHarness.reply({
          'error': 'conflict',
          'message': '',
          'reason': 'last_owner',
          'orgs': ['Acme'],
        }, 409);
    await t.tap(find.byKey(Key('member-remove-$mia')));
    await t.pump();
    await t.tap(find.byKey(const Key('confirm-yes')));
    await pumpReal(t);
    expect(
      find.text('Last owner of: Acme. Name another owner first.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('org-leave')), findsOneWidget);
  });

  testWidgets('invite: link and file, mail state, pending list with revoke', (
    t,
  ) async {
    final s = await admin(t);
    final id = newId();
    h.orgReplies['POST /orgs/$testOrgId/invites'] = (b) => SyncHarness.reply({
      'invite': {
        'id': id,
        'email': b['email'],
        'role': b['role'],
        'expiresAt': '2026-10-22T12:00:00.000Z',
        'link':
            'unfeudal://enroll?server=https://vault.test&token=${'t' * 43}&kind=invite',
        'file': '{"unfeudal-enroll":1}',
      },
      'mailSent': false,
    }, 201);
    h.orgReplies['GET /orgs/$testOrgId/invites'] = (_) => SyncHarness.reply({
      'invites': [
        {
          'id': id,
          'email': 'new@example.org',
          'role': 'member',
          'createdBy': s.stored!.userId,
          'createdAt': '2026-10-15T12:00:00.000Z',
          'expiresAt': '2026-10-22T12:00:00.000Z',
        },
      ],
    });
    await pumpApp(
      t,
      state: s,
      child: const InviteDialog(orgId: testOrgId),
    );
    await t.enterText(find.byKey(const Key('invite-email')), 'new@example.org');
    await t.tap(find.byKey(const Key('invite-create')));
    await pumpReal(t);
    expect(
      find.text('No email sent: share the link or the file.'),
      findsOneWidget,
    );
    expect(find.textContaining('unfeudal://enroll'), findsOneWidget);
    await t.tap(find.byKey(Key('invite-revoke-$id')));
    await pumpReal(t);
    expect(h.orgCalls.last.route, 'DELETE /invites/$id');
  });
}
