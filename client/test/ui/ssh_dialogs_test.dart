// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/design/motion.dart';
import 'package:unfeudal_client/src/ssh/ssh_connector.dart';
import 'package:unfeudal_client/src/ui/terminal/ssh_dialogs.dart';

import '../support/pump_app.dart';

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
  testWidgets('startup command: shown in mono, run returns true', (t) async {
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
  });

  testWidgets('startup command: skip returns false', (t) async {
    final r = await open<bool>(
      t,
      const StartupCommandDialog(hostName: 'db1', command: 'tmux attach'),
    );
    await t.tap(find.byKey(const Key('startup-skip')));
    await t.pumpAndSettle();
    expect(await r, isFalse);
  });

  testWidgets('keyboard-interactive hides non-echo answers and returns them', (
    t,
  ) async {
    final r = await open<List<String>>(
      t,
      const KeyboardInteractiveDialog(
        name: 'otp',
        instruction: '',
        prompts: [
          SshPrompt('Code: ', echo: true),
          SshPrompt('Password: ', echo: false),
        ],
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
