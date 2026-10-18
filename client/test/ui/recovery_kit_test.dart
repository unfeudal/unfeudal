// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/ui/onboarding/recovery_kit_view.dart';

import '../support/pump_app.dart';

const sampleWords =
    'ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ23-4567-ABCD-EFGH-IJKL-MNOP-Q';

void main() {
  test('text kit: the contract lines', () {
    final text = recoveryKitText(
      server: Uri.parse('https://vault.example.org'),
      email: 'camille@example.org',
      created: DateTime.utc(2026, 10, 15),
      recoveryKey: sampleWords,
      instructions: 'Keep it offline.',
    );
    expect(text.split('\n').take(5), [
      'Server: https://vault.example.org',
      'Account: camille@example.org',
      'Created: 2026-10-15',
      '',
      sampleWords,
    ]);
    expect(text, contains('Keep it offline.'));
  });

  test('PDF kit is one A4 page', () async {
    final pdf = await buildRecoveryKitPdf(
      server: Uri.parse('https://vault.example.org'),
      email: 'camille@example.org',
      created: DateTime.utc(2026, 10, 15),
      recoveryKey: sampleWords,
      instructions: 'Keep it offline.',
    );
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    expect(
      RegExp(r'/Type\s*/Page[^s]').allMatches(
        String.fromCharCodes(pdf),
      ), // the pdf package writes `/Type/Page`
      hasLength(1),
    );
  });

  testWidgets(
    'continue needs the confirmation; save writes txt or pdf; print opens the dialog',
    (t) async {
      final saved = <String, Uint8List>{};
      Uint8List? printed;
      var done = 0;
      await pumpApp(
        t,
        child: RecoveryKitView(
          recoveryKey: sampleWords,
          server: Uri.parse('https://vault.example.org'),
          email: 'camille@example.org',
          onDone: () => done++,
          savePath: (name) async => '/tmp/kit.txt',
          writeFile: (path, bytes) async => saved[path] = bytes,
          printPdf: (bytes) async => printed = bytes,
        ),
      );
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('recovery-continue')))
            .onPressed,
        isNull,
      );
      await t.tap(find.byKey(const Key('recovery-save')));
      await pumpReal(t, rounds: 5);
      expect(
        String.fromCharCodes(saved['/tmp/kit.txt']!),
        contains(sampleWords),
      );
      await t.tap(find.byKey(const Key('recovery-print')));
      await pumpReal(t, rounds: 10);
      expect(printed, isNotNull);
      await t.tap(find.byKey(const Key('recovery-confirm')));
      await t.pump();
      await t.tap(find.byKey(const Key('recovery-continue')));
      expect(done, 1);
    },
  );

  testWidgets('copy clears the clipboard after 60 s and on close', (t) async {
    final clip = <String?>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clip.add((call.arguments as Map)['text'] as String?);
        }
        if (call.method == 'Clipboard.getData') {
          return {'text': clip.isEmpty ? null : clip.last};
        }
        return null;
      },
    );
    await pumpApp(
      t,
      child: RecoveryKitView(recoveryKey: sampleWords, onDone: () {}),
    );
    await t.tap(find.byKey(const Key('recovery-copy')));
    await t.pump();
    expect(clip.last, sampleWords);
    await t.pump(const Duration(seconds: 60));
    await t.pump();
    expect(clip.last, '');
    await t.tap(find.byKey(const Key('recovery-copy')));
    await t.pump();
    await t.pumpWidget(const SizedBox());
    await t.pump();
    expect(clip.last, '');
  });
}
