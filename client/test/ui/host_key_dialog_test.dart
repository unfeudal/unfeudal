// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/design/motion.dart';
import 'package:unfeudal_client/src/ssh/ssh_connector.dart';
import 'package:unfeudal_client/src/ui/hosts/host_key_dialog.dart';
import 'package:unfeudal_client/src/ui/terminal/ssh_dialogs.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/pump_app.dart';

final pinned = KnownHostMeta.fromJson({
  'schemaVersion': 1,
  'hostItemId': newId(),
  'keyType': 'ssh-ed25519',
  'sha256Fingerprint': 'SHA256:${'A' * 43}',
});
HostKeyCheck check(HostKeyDecision d) => HostKeyCheck(
  hostId: pinned.hostItemId,
  hostName: 'Prod-DB',
  keyType: 'ssh-ed25519',
  fingerprint: 'SHA256:${'B' * 43}',
  decision: d,
  pinned: d == HostKeyDecision.changed ? pinned : null,
);

Future<Future<T?>> open<T>(WidgetTester t, Widget dialog) async {
  late BuildContext ctx;
  await pumpApp(
    t,
    child: Builder(
      builder: (c) {
        ctx = c;
        return const SizedBox();
      },
    ),
  );
  final result = showUfDialog<T>(ctx, (_) => dialog, alert: true);
  await t.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('unknown key: fingerprint in mono, trust returns true', (
    t,
  ) async {
    final r = await open<bool>(
      t,
      HostKeyUnknownDialog(check: check(HostKeyDecision.unknown)),
    );
    expect(
      t.widget<Text>(find.text('SHA256:${'B' * 43}')).style!.fontFamily,
      'JetBrainsMono',
    );
    await t.tap(find.byKey(const Key('hostkey-trust')));
    await t.pumpAndSettle();
    expect(await r, isTrue);
  });

  testWidgets('accept stays disabled until the exact host name is typed', (
    t,
  ) async {
    final r = await open<bool>(
      t,
      HostKeyChangedDialog(check: check(HostKeyDecision.changed)),
    );
    expect(find.text('SHA256:${'A' * 43}'), findsOneWidget);
    expect(find.text('SHA256:${'B' * 43}'), findsOneWidget);
    TextButton accept() =>
        t.widget<TextButton>(find.byKey(const Key('hostkey-accept')));
    expect(accept().onPressed, isNull);
    await t.enterText(
      find.byKey(const Key('hostkey-confirm-input')),
      'prod-db',
    );
    await t.pump();
    expect(accept().onPressed, isNull);
    await t.enterText(
      find.byKey(const Key('hostkey-confirm-input')),
      'Prod-DB',
    );
    await t.pump();
    await t.tap(find.byKey(const Key('hostkey-accept')));
    await t.pumpAndSettle();
    expect(await r, isTrue);
  });

  testWidgets('escape refuses the changed key', (t) async {
    final r = await open<bool>(
      t,
      HostKeyChangedDialog(check: check(HostKeyDecision.changed)),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(await r, isNot(true));
  });

  testWidgets(
    'startup command: shown in mono, run returns true, skip returns false',
    (t) async {
      final r = await open<bool>(
        t,
        const StartupCommandDialog(hostName: 'db1', command: 'tmux attach'),
      );
      expect(
        t.widget<EditableText>(find.text('tmux attach')).style.fontFamily,
        'JetBrainsMono',
      );
      await t.tap(find.byKey(const Key('startup-run')));
      await t.pumpAndSettle();
      expect(await r, isTrue);
      final skipped = await open<bool>(
        t,
        const StartupCommandDialog(hostName: 'db1', command: 'tmux attach'),
      );
      await t.tap(find.byKey(const Key('startup-skip')));
      await t.pumpAndSettle();
      expect(await skipped, isFalse);
    },
  );

  testWidgets('keyboard-interactive hides non-echo answers and returns them', (
    t,
  ) async {
    final r = await open<List<String>>(
      t,
      const KeyboardInteractiveDialog(
        name: 'otp',
        instruction: '',
        prompts: [SshPrompt('Code: ', true), SshPrompt('Password: ', false)],
      ),
    );
    final fields = t.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.map((f) => f.obscureText), [false, true]);
    await t.enterText(find.byType(TextField).first, '123456');
    await t.enterText(find.byType(TextField).last, 'pw');
    await t.tap(find.byKey(const Key('prompts-ok')));
    await t.pumpAndSettle();
    expect(await r, ['123456', 'pw']);
  });
}
