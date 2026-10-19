// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/api/api_client.dart';
import 'package:unfeudal_client/src/audit/activity_model.dart';
import 'package:unfeudal_client/src/audit/audit_anchors.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';

import '../support/org_fixtures.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

Future<(SyncHarness, ApiClient, String)> signedIn() async {
  final h = SyncHarness();
  final login = await h.signIn();
  return (
    h,
    ApiClient(h.baseUrl, h.client)
      ..accessToken = login.accessToken
      ..refreshToken = login.refreshToken,
    login.account.userId,
  );
}

void main() {
  test(
    'pages a view; verify and export page the whole chain; file names',
    () async {
      final (h, api, me) = await signedIn();
      for (var i = 0; i < 150; i++) {
        h.appendAudit('user:$me', 'device.added', actorUser: me);
      }
      final m = ActivityModel(
        api: api,
        anchors: AuditAnchors(LocalMirror.inMemory()),
        userId: me,
        scope: 'me',
      );
      await m.load();
      expect([m.events.length, m.hasMore], [100, true]);
      await m.more();
      expect([m.events.length, m.hasMore], [150, false]);
      expect((await m.verify()).ok, isTrue);
      expect(
        h.requests.where((r) => r == 'GET /api/v1/audit'),
        hasLength(3),
        reason: 'verify reads the user chain at 500 a page',
      );
      expect(jsonDecode(await m.exportJson()) as List, hasLength(150));
      expect(
        [
          ActivityModel.exportFileName('org:$testOrgId'),
          ActivityModel.exportFileName('user'),
        ],
        ['unfeudal-audit-org-$testOrgId.json', 'unfeudal-audit-user.json'],
      );
      expect(
        [
          ActivityModel.chainOf('me'),
          ActivityModel.chainOf('folder:$testOrgId'),
          ActivityModel.chainOf('instance'),
        ],
        ['user', null, 'instance'],
      );
    },
  );

  test('a rewrite seen by a later read raises an alert', () async {
    final (h, api, me) = await signedIn();
    for (var i = 0; i < 3; i++) {
      h.appendAudit('user:$me', 'device.added', actorUser: me);
    }
    final anchors = AuditAnchors(LocalMirror.inMemory());
    await ActivityModel(
      api: api,
      anchors: anchors,
      userId: me,
      scope: 'user',
    ).load();
    h.rewriteAudit('user:$me', 2, 'item.created');
    final again = ActivityModel(
      api: api,
      anchors: anchors,
      userId: me,
      scope: 'user',
    );
    await again.load();
    expect(again.alerts.single.kind, AnchorAlertKind.rewritten);
  });

  test(
    'a whole chain served empty after this device saw it is reported on verify',
    () async {
      final (h, api, me) = await signedIn();
      for (var i = 0; i < 3; i++) {
        h.appendAudit('user:$me', 'device.added', actorUser: me);
      }
      final anchors = AuditAnchors(LocalMirror.inMemory());
      await ActivityModel(
        api: api,
        anchors: anchors,
        userId: me,
        scope: 'user',
      ).load();
      h.auditLog.clear();
      final m = ActivityModel(
        api: api,
        anchors: anchors,
        userId: me,
        scope: 'me',
      );
      expect((await m.verify()).ok, isTrue, reason: 'an empty chain verifies');
      expect(m.alerts.single.kind, AnchorAlertKind.vanished);
    },
  );

  testWidgets('describeEvent: local names, raw action for unknown ones', (
    t,
  ) async {
    await pumpApp(t, child: const SizedBox());
    final l = AppLocalizations.of(t.element(find.byType(SizedBox).first));
    final h = SyncHarness();
    String nameOf(String id) =>
        {
          'h1': 'prod-web-1',
          'f1': 'Prod',
          'root': 'top level',
          'forward:5432': '5432',
        }[id] ??
        id;
    String say(String action, List<String> targets) => describeEvent(
      l,
      h.appendAudit('instance', action, targets: targets),
      nameOf,
    );
    expect(say('item.moved', ['h1', 'root', 'f1']), 'prod-web-1 moved to Prod');
    expect(
      say('ssh.forward_started', ['h1', 'forward:5432']),
      'Forward 5432 started on prod-web-1',
    );
    expect(say('ssh.session_opened', ['h1']), 'Connected to prod-web-1');
    expect(say('future.thing', []), 'future.thing');
  });
}
