// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/ui/settings/export_screen.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets(
    'encrypted: a confirmed passphrase of 12 characters or more, then saved',
    (t) async {
      final s = await signedInState(t);
      final saved = <String, List<int>>{};
      await pumpApp(
        t,
        state: s,
        child: ExportScreen(
          savePath: (name) async => '/tmp/$name',
          writeFile: (p, b) async => saved[p] = b,
        ),
      );
      Future<void> submit(String pass) async {
        await t.enterText(find.byKey(const Key('export-passphrase')), pass);
        await t.enterText(
          find.byKey(const Key('export-passphrase-confirm')),
          pass,
        );
        await t.tap(find.byKey(const Key('export-submit')));
        await pumpReal(t, rounds: 40);
      }

      await submit('too short');
      expect(saved, isEmpty);
      await submit('twelve chars!');
      expect(
        saved.keys.single,
        matches(RegExp(r'^/tmp/unfeudal-export-\d{4}-\d{2}-\d{2}\.json$')),
      );
      expect(
        jsonDecode(utf8.decode(saved.values.single))['format'],
        'unfeudal-export',
      );
    },
  );

  testWidgets('plaintext needs the explicit confirmation', (t) async {
    final s = await signedInState(t);
    final saved = <String, List<int>>{};
    await pumpApp(
      t,
      state: s,
      child: ExportScreen(
        savePath: (name) async => '/tmp/$name',
        writeFile: (p, b) async => saved[p] = b,
      ),
    );
    await t.tap(find.byKey(const Key('export-plain')));
    await t.pump();
    await t.tap(find.byKey(const Key('export-submit')));
    await pumpReal(t, rounds: 10);
    expect(saved, isEmpty);
    await t.tap(find.byKey(const Key('export-plain-confirm')));
    await t.tap(find.byKey(const Key('export-submit')));
    await pumpReal(t, rounds: 20);
    expect(
      jsonDecode(utf8.decode(saved.values.single))['format'],
      'unfeudal-export-plain',
    );
  });
}
