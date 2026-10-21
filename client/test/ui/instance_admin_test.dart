// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/ui/admin/instance_admin_screen.dart';
import 'package:unfeudal_client/src/ui/settings/settings_screen.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  late SyncHarness h;
  final user = newId(), org = newId();
  Future<AppState> open(WidgetTester t) async {
    h = SyncHarness(capabilities: ['orgs', 'sync']);
    final s = await signedInState(t, harness: h);
    h.orgReplies['GET /admin/users'] = (_) => SyncHarness.reply({
      'users': [
        {
          'id': s.stored!.userId,
          'email': 'camille@example.org',
          'disabled': false,
          'isInstanceOwner': true,
          'createdAt': '2026-10-15T12:00:00.000Z',
        },
        {
          'id': user,
          'email': 'bob@example.org',
          'disabled': false,
          'isInstanceOwner': false,
          'createdAt': '2026-10-15T12:00:00.000Z',
        },
      ],
    });
    h.orgReplies['GET /admin/orgs'] = (_) => SyncHarness.reply({
      'orgs': [
        {
          'id': org,
          'name': 'Acme',
          'owners': ['bob@example.org'],
          'memberCount': 4,
          'storageBytes': 2097152,
          'lastActivityAt': null,
        },
      ],
    });
    h.orgReplies['GET /admin/invites'] = (_) =>
        SyncHarness.reply({'invites': <Object?>[]});
    await pumpApp(
      t,
      state: s,
      child: const Scaffold(body: InstanceAdminPanel()),
    );
    await pumpReal(t);
    return s;
  }

  testWidgets('Settings shows the Server group to the Instance Owner', (
    t,
  ) async {
    final s = await signedInState(t);
    await pumpApp(t, state: s, child: const SettingsScreen());
    expect(
      find.byKey(const Key('group-server')),
      findsOneWidget,
      reason: 'the first account is the Instance Owner',
    );
  });

  testWidgets(
    'accounts: no action on the Instance Owner; disable and delete others',
    (t) async {
      final s = await open(t);
      expect(
        find.byKey(Key('admin-user-disable-${s.stored!.userId}')),
        findsNothing,
      );
      await t.tap(find.byKey(Key('admin-user-disable-$user')));
      await pumpReal(t);
      expect(h.orgCalls.last.route, 'PUT /admin/users/$user');
      expect(h.orgCalls.last.body, {'disabled': true});
      await t.tap(find.byKey(Key('admin-user-delete-$user')));
      await t.pump();
      await t.tap(find.byKey(const Key('confirm-yes')));
      await pumpReal(t);
      expect(h.orgCalls.last.route, 'DELETE /admin/users/$user');
    },
  );

  testWidgets('orgs: metadata only; delete needs the exact name', (t) async {
    await open(t);
    await t.tap(find.byKey(const Key('admin-tab-orgs')));
    await t.pumpAndSettle();
    expect(find.textContaining('bob@example.org'), findsOneWidget);
    expect(find.text('2 MB'), findsOneWidget);
    await t.tap(find.byKey(Key('admin-org-delete-$org')));
    await t.pump();
    await t.enterText(find.byKey(const Key('admin-org-confirm-name')), 'Acme');
    await t.pump();
    await t.tap(find.byKey(const Key('admin-org-delete-ok')));
    await pumpReal(t);
    expect(h.orgCalls.last.route, 'DELETE /admin/orgs/$org');
    expect(h.orgCalls.last.body, {'confirmName': 'Acme'});
  });

  testWidgets(
    'invites: create shows the link, revoke uses DELETE /invites/{id}',
    (t) async {
      await open(t);
      final id = newId();
      h.orgReplies['POST /admin/invites'] = (b) => SyncHarness.reply({
        'invite': {
          'id': id,
          'email': b['email'],
          'role': null,
          'expiresAt': '2026-10-22T12:00:00.000Z',
          'link':
              'unfeudal://enroll?server=https://vault.test&token=${'t' * 43}&kind=invite',
          'file': '{"unfeudal-enroll":1}',
        },
        'mailSent': true,
      }, 201);
      h.orgReplies['GET /admin/invites'] = (_) => SyncHarness.reply({
        'invites': [
          {
            'id': id,
            'email': 'new@example.org',
            'createdBy': newId(),
            'createdAt': '2026-10-15T12:00:00.000Z',
            'expiresAt': '2026-10-22T12:00:00.000Z',
          },
        ],
      });
      await t.tap(find.byKey(const Key('admin-tab-invites')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('admin-invite-email')),
        'new@example.org',
      );
      await t.tap(find.byKey(const Key('admin-invite-create')));
      await pumpReal(t);
      expect(find.text('Invitation sent by email.'), findsOneWidget);
      await t.tap(find.byKey(Key('invite-revoke-$id')));
      await pumpReal(t);
      expect(h.orgCalls.last.route, 'DELETE /invites/$id');
    },
  );
}
