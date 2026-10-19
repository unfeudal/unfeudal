// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/ui/hosts/folder_editor_panel.dart';
import 'package:unfeudal_client/src/ui/hosts/host_editor_panel.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';

ButtonStyleButton button(WidgetTester t, String key) =>
    t.widget<ButtonStyleButton>(find.byKey(Key(key)));

FolderMeta jumpFolder(String jump) => FolderMeta.fromJson({
  'schemaVersion': 1,
  'name': 'prod',
  'defaults': {
    'port': null,
    'user': null,
    'identityId': null,
    'jumpHostId': jump,
  },
});

void main() {
  testWidgets(
    'forwards: low port needs the opt-in, duplicate and invalid rows block save',
    (t) async {
      final s = await signedInState(t);
      late String id;
      await t.runAsync(
        () async => id = await s.vault!.upsertItem(
          type: 'host',
          meta: hostJson('web', user: 'root'),
        ),
      );
      await pumpApp(
        t,
        state: s,
        child: HostEditorPanel(hostId: id),
      );
      final l = AppLocalizations.of(t.element(find.byType(HostEditorPanel)));
      Future<void> row(int i, String local, String host, String remote) async {
        await t.tap(find.byKey(const Key('forward-add')));
        await t.pump();
        await t.enterText(find.byKey(Key('forward-local-$i')), local);
        await t.enterText(find.byKey(Key('forward-host-$i')), host);
        await t.enterText(find.byKey(Key('forward-remote-$i')), remote);
        await t.pump();
      }

      await row(0, '80', 'db.internal', '5432');
      expect(find.text(l.forwardLowPort), findsOneWidget);
      expect(button(t, 'host-save').onPressed, isNull);
      await t.tap(find.byKey(const Key('forward-low-0')));
      await t.pump();
      expect(button(t, 'host-save').onPressed, isNotNull);
      await row(1, '8080', 'db internal', '70000');
      expect(find.text(l.fieldInvalid), findsWidgets);
      await row(2, '80', 'cache', '6379');
      await t.tap(find.byKey(const Key('forward-low-2')));
      await t.pump();
      expect(find.text(l.forwardDuplicate), findsOneWidget);
      expect(button(t, 'host-save').onPressed, isNull);
      await t.tap(find.byKey(const Key('forward-remove-2')));
      await t.pump();
      await t.tap(find.byKey(const Key('forward-remove-1')));
      await t.pump();
      await t.tap(find.byKey(const Key('host-save')));
      await pumpReal(t, rounds: 10);
      expect(s.vault!.entry(id)!.meta!['forwards'], [
        {
          'localPort': 80,
          'remoteHost': 'db.internal',
          'remotePort': 5432,
          'autoStart': false,
          'allowLowPorts': true,
        },
      ]);
    },
  );

  testWidgets('at most 32 forwards', (t) async {
    final s = await signedInState(t);
    late String id;
    await t.runAsync(
      () async => id = await s.vault!.upsertItem(
        type: 'host',
        meta: {
          ...hostJson('web'),
          'forwards': [
            for (var i = 0; i < 32; i++)
              {
                'localPort': 20000 + i,
                'remoteHost': 'h',
                'remotePort': 22,
                'autoStart': false,
              },
          ],
        },
      ),
    );
    await pumpApp(
      t,
      state: s,
      child: HostEditorPanel(hostId: id),
    );
    expect(button(t, 'forward-add').onPressed, isNull);
  });

  testWidgets(
    'jump host: inherited value shown with its folder; self and loop-making hosts not offered',
    (t) async {
      final s = await signedInState(t);
      late String other, web, viaWeb;
      await t.runAsync(() async {
        final v = s.vault!;
        final bastion = await v.upsertItem(
          type: 'host',
          meta: hostJson('bastion'),
        );
        other = await v.upsertItem(type: 'host', meta: hostJson('other'));
        final prod = await v.saveFolder(jumpFolder(bastion));
        web = await v.upsertItem(
          type: 'host',
          folderId: prod,
          meta: hostJson('web'),
        );
        viaWeb = await v.upsertItem(
          type: 'host',
          meta: {...hostJson('via-web'), 'jumpHostId': web},
        );
      });
      await pumpApp(
        t,
        state: s,
        child: HostEditorPanel(hostId: web),
      );
      final l = AppLocalizations.of(t.element(find.byType(HostEditorPanel)));
      final picker = find.byKey(const Key('jump-picker'));
      expect(
        find.descendant(
          of: picker,
          matching: find.text(l.hostInherited('prod')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: picker, matching: find.text('bastion')),
        findsOneWidget,
      );
      await t.tap(picker);
      await t.pumpAndSettle();
      expect(find.byKey(Key('jump-option-$web')), findsNothing);
      expect(find.byKey(Key('jump-option-$viaWeb')), findsNothing);
      await t.tap(find.byKey(Key('jump-option-$other')).last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('host-save')));
      await pumpReal(t, rounds: 10);
      expect(s.vault!.entry(web)!.meta!['jumpHostId'], other);
    },
  );

  testWidgets(
    'folder editor sets the default jump host; a bastion inside the folder connects directly',
    (t) async {
      final s = await signedInState(t);
      late String prod, bastion, web;
      await t.runAsync(() async {
        prod = await s.vault!.saveFolder(
          FolderMeta.fromJson(folderJson('prod')),
        );
        bastion = await s.vault!.upsertItem(
          type: 'host',
          folderId: prod,
          meta: hostJson('bastion'),
        );
        web = await s.vault!.upsertItem(
          type: 'host',
          folderId: prod,
          meta: hostJson('web'),
        );
      });
      await pumpApp(
        t,
        state: s,
        child: FolderEditorPanel(folderId: prod),
      );
      await t.tap(find.byKey(const Key('folder-jump')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(Key('jump-option-$bastion')).last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('folder-save')));
      await pumpReal(t, rounds: 10);
      expect(
        FolderMeta.fromJson(s.vault!.entry(prod)!.meta!).defaults.jumpHostId,
        bastion,
      );
      expect(
        (
          s.vault!.resolve(bastion).jumpHostId,
          s.vault!.resolve(web).jumpHostId,
        ),
        (null, bastion),
      );
    },
  );
}
