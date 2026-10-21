// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/design/tokens.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/org_fixtures.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  Future<(SyncHarness, AppState, Item)> withOrg(
    WidgetTester t, {
    String status = 'confirmed',
    List<String> caps = const [],
  }) async {
    final h = SyncHarness(
      capabilities: [
        'mascot',
        'orgs',
        'recovery_kit',
        'reveal',
        'sync',
        ...caps,
      ],
    );
    final s = await signedInState(t, harness: h);
    final me = s.stored!.userId;
    final keys = FolderKeys.generate(1), f = newId();
    h.orgMembers[testOrgId] = {me};
    late Item host;
    await t.runAsync(() async {
      final pub = h.accounts.values.first.bundle.publicKey;
      host = h.serverPutOrg(
        await sealOrgItem(keys, folderId: f, meta: hostJson('org-db')),
      );
      final folder = h.serverPutOrg(
        await sealOrgItem(
          keys,
          id: f,
          type: 'folder',
          meta: folderJson('Prod'),
        ),
      );
      h.orgBlock = status == 'accepted'
          ? orgBlock(status: 'accepted')
          : orgBlock(
              members: [memberRow(me)],
              folderTree: [node(f)],
              acl: [
                aclRow(f, me, allow: ['edit']),
              ],
              wrappedKeys: [await wrappedRow(keys, f, pub)],
              itemIds: [host.id, folder.id],
            );
      await s.sync!.syncNow();
    });
    await pumpApp(t, state: s);
    return (h, s, host);
  }

  testWidgets(
    'one menu entry per org; the tree shows the selected vault only',
    (t) async {
      final (_, s, host) = await withOrg(t);
      expect(find.byKey(Key('host-${host.id}')), findsNothing);
      await openVaults(t);
      expect(find.byKey(const Key('vault-personal')), findsOneWidget);
      await t.tap(find.byKey(const Key('vault-org-$testOrgId')));
      await t.pumpAndSettle();
      expect(find.byKey(Key('host-${host.id}')), findsOneWidget);
    },
  );

  testWidgets('an accepted member sees the org name and a waiting note', (
    t,
  ) async {
    final (h, _, _) = await withOrg(t, status: 'accepted');
    await openVaults(t);
    await t.tap(find.byKey(const Key('vault-org-$testOrgId')));
    await t.pumpAndSettle();
    expect(find.text(l10n(t).orgAwaiting), findsWidgets);
    // leaving needs no confirmation by an admin
    await t.tap(find.byKey(const Key('org-awaiting-leave')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirm-yes')));
    await pumpReal(t);
    expect(
      h.orgCalls.first.route,
      startsWith('DELETE /orgs/$testOrgId/members/'),
    );
  });

  testWidgets('no org UI without the orgs capability', (t) async {
    final s = await signedInState(t);
    await pumpApp(t, state: s);
    await openVaults(t);
    expect(find.byKey(const Key('vault-new-org')), findsNothing);
    expect(find.byKey(const Key('vault-join-org')), findsNothing);
  });

  testWidgets('the open vault selector shows a focus ring outside a gap', (
    t,
  ) async {
    final s = await signedInState(t);
    await pumpApp(t, state: s);
    await openVaults(t);
    final selector = find.byKey(const Key('vault-selector'));
    final colors = UfColors.of(t.element(selector));
    final box = t.widget<AnimatedContainer>(
      find
          .ancestor(of: selector, matching: find.byType(AnimatedContainer))
          .first,
    );
    // painted in order: the 4 px focus first, the 2 px gap over it
    expect(
      [
        for (final s in (box.decoration! as BoxDecoration).boxShadow!)
          (s.color, s.spreadRadius),
      ],
      [(colors.focus, 4), (colors.bg, 2)],
    );
  });

  testWidgets('create an org and join one with a link', (t) async {
    final (h, _, _) = await withOrg(t);
    h.orgReplies['POST /orgs'] = (_) => SyncHarness.reply({
      'org': {'id': newId(), 'name': 'Beta', 'role': 'owner'},
    }, 201);
    h.orgReplies['POST /invites/join'] = (_) =>
        SyncHarness.reply({'orgId': testOrgId});
    await openVaults(t);
    await t.tap(find.byKey(const Key('vault-new-org')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('org-name')), 'Beta');
    await t.tap(find.byKey(const Key('org-create')));
    await pumpReal(t);
    expect(h.orgCalls.last.body, {'name': 'Beta'});
    await openVaults(t);
    await t.tap(find.byKey(const Key('vault-join-org')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('join-link')), 'nonsense');
    await t.tap(find.byKey(const Key('join-submit')));
    await t.pump();
    expect(find.text(l10n(t).joinInvalid), findsOneWidget);
    final token = 'A' * 43;
    await t.enterText(
      find.byKey(const Key('join-link')),
      'unfeudal://enroll?server=https://vault.test&token=$token&kind=invite',
    );
    await t.tap(find.byKey(const Key('join-submit')));
    await pumpReal(t);
    expect(h.orgCalls.last.route, 'POST /invites/join');
    expect(h.orgCalls.last.body, {'token': token});
  });

  testWidgets('new org folder is disabled offline', (t) async {
    final (h, s, _) = await withOrg(t);
    await openVaults(t);
    await t.tap(find.byKey(const Key('vault-org-$testOrgId')));
    await t.pumpAndSettle();
    h.offline = true;
    await t.runAsync(() => s.sync!.syncNow());
    await t.pump();
    final button = t.widget<IconButton>(
      find.byKey(const Key('tree-new-folder')),
    );
    expect(button.onPressed, isNull);
  });
}

AppLocalizations l10n(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byKey(const Key('vault-selector'))));

/// Opens the vault selector's menu.
Future<void> openVaults(WidgetTester t) async {
  await t.tap(find.byKey(const Key('vault-selector')));
  await t.pumpAndSettle();
}
