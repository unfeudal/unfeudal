// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/ui/hosts/folder_editor_panel.dart';
import 'package:unfeudal_client/src/ui/hosts/host_editor_panel.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';

AppLocalizations l10n(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(Scaffold).first));

void main() {
  testWidgets(
    'new host: required fields, invalid port refused, saved with HostCreated',
    (t) async {
      final s = await signedInState(t);
      final events = <AppEvent>[];
      s.events.listen(events.add);
      await pumpApp(t, state: s, child: const HostEditorPanel());
      await t.tap(find.byKey(const Key('host-save')));
      await t.pump();
      expect(find.text(l10n(t).fieldRequired), findsNWidgets(2));
      await t.enterText(find.byKey(const Key('host-name')), 'web');
      await t.enterText(find.byKey(const Key('host-address')), '10.0.0.5');
      await t.enterText(find.byKey(const Key('host-port')), '70000');
      await t.tap(find.byKey(const Key('host-save')));
      await t.pump();
      expect(find.text(l10n(t).fieldInvalid), findsOneWidget);
      await t.enterText(find.byKey(const Key('host-port')), '');
      await t.tap(find.byKey(const Key('host-save')));
      await pumpReal(t, rounds: 10);
      expect(s.vault!.ofKind(ItemKind.host).single.name, 'web');
      expect(events.whereType<HostCreated>().single.name, 'web');
    },
  );

  testWidgets('inherited values are shown greyed with their source', (t) async {
    final s = await signedInState(t);
    late String host;
    await t.runAsync(() async {
      final top = await s.vault!.saveFolder(
        FolderMeta.fromJson(folderJson('top', port: 2222)),
      );
      host = await s.vault!.upsertItem(
        type: 'host',
        folderId: top,
        meta: hostJson('web'),
      );
    });
    await pumpApp(
      t,
      state: s,
      child: HostEditorPanel(hostId: host),
    );
    final port = t.widget<TextField>(find.byKey(const Key('host-port')));
    expect(
      (port.decoration!.hintText, port.decoration!.helperText),
      ('2222', l10n(t).hostInherited('top')),
    );
    final user = t.widget<TextField>(find.byKey(const Key('host-user')));
    expect(user.decoration!.helperText, l10n(t).hostDefault);
  });

  testWidgets('saving keeps the fields this editor does not show', (t) async {
    final s = await signedInState(t);
    late String host;
    await t.runAsync(
      () async => host = await s.vault!.upsertItem(
        type: 'host',
        meta: {
          ...hostJson('web'),
          'forwards': [
            {
              'localPort': 8443,
              'remoteHost': '127.0.0.1',
              'remotePort': 443,
              'autoStart': false,
            },
          ],
          'jumpHostId': newId(),
          'colorLabel': 'red',
        },
      ),
    );
    await pumpApp(
      t,
      state: s,
      child: HostEditorPanel(hostId: host),
    );
    await t.enterText(find.byKey(const Key('host-name')), 'web2');
    await t.tap(find.byKey(const Key('host-save')));
    await pumpReal(t, rounds: 10);
    final meta = s.vault!.entry(host)!.meta!;
    expect(meta['name'], 'web2');
    expect(meta['colorLabel'], 'red');
    expect((meta['forwards'] as List).length, 1);
    expect(meta['jumpHostId'], isNotNull);
  });

  testWidgets('newer payload and trashed host are read-only', (t) async {
    final s = await signedInState(t);
    late String newer, trashed;
    await t.runAsync(() async {
      final item = await sealItem(
        s.vault!.debugKey,
        meta: {...hostJson('n'), 'schemaVersion': 2},
      );
      s.mirror!.upsertItems([item]);
      newer = item.id;
      trashed = await s.vault!.upsertItem(type: 'host', meta: hostJson('t'));
      await s.vault!.trashItem(trashed);
      await s.vault!.reload();
    });
    await pumpApp(
      t,
      state: s,
      child: HostEditorPanel(hostId: newer),
    );
    expect(find.text(l10n(t).itemNewer), findsOneWidget);
    expect(find.byKey(const Key('host-save')), findsNothing);
    await pumpApp(
      t,
      state: s,
      child: HostEditorPanel(hostId: trashed),
    );
    expect(find.text(l10n(t).itemTrashed), findsOneWidget);
    expect(find.byKey(const Key('host-save')), findsNothing);
  });

  testWidgets(
    'folder editor: parent cannot be inside itself; delete asks, then trashes',
    (t) async {
      final s = await signedInState(t);
      late String top, sub;
      await t.runAsync(() async {
        top = await s.vault!.saveFolder(FolderMeta.fromJson(folderJson('top')));
        sub = await s.vault!.saveFolder(
          FolderMeta.fromJson(folderJson('sub')),
          parentId: top,
        );
      });
      await pumpApp(
        t,
        state: s,
        child: FolderEditorPanel(folderId: top),
      );
      await t.tap(find.byKey(const Key('folder-parent')));
      await t.pumpAndSettle();
      expect(find.byKey(Key('folder-parent-$sub')), findsNothing);
      expect(find.byKey(Key('folder-parent-$top')), findsNothing);
      await t.tapAt(Offset.zero);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('folder-delete')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirm-yes')));
      await pumpReal(t, rounds: 10);
      expect((s.vault!.isTrashed(top), s.vault!.isTrashed(sub)), (true, true));
    },
  );
}
