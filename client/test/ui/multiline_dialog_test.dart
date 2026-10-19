// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/ui/terminal/multiline_dialog.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('only the send button says yes', (t) async {
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
    var r = confirmUnsafeMultiline(ctx);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('multiline-cancel')));
    await t.pumpAndSettle();
    expect(await r, isFalse);
    r = confirmUnsafeMultiline(ctx);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(await r, isFalse);
    r = confirmUnsafeMultiline(ctx);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('multiline-send')));
    await t.pumpAndSettle();
    expect(await r, isTrue);
  });
}
