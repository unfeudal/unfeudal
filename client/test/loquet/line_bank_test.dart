// SPDX-License-Identifier: Apache-2.0
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/loquet/line_bank.dart';
import 'package:unfeudal_client/src/loquet/loquet_pose.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final fr = lookupAppLocalizations(const Locale('fr'));
  const params = {'name': 'Camille', 'method': 'Windows Hello'};

  test('every key has text in both languages, within the voice rules', () {
    final bank = LineBank(random: Random(1));
    for (final k in LineKey.values) {
      for (final l in [en, fr]) {
        for (var i = 0; i < 6; i++) {
          final s = bank.text(l, k, params);
          expect(
            s.split(RegExp(r'\s+')).length,
            lessThanOrEqualTo(12),
            reason: '$k: $s',
          );
          expect(s, isNot(contains('!')), reason: '$k: $s');
        }
      }
    }
  });

  test('French lines use neutral forms', () {
    final bank = LineBank(random: Random(2));
    const banned = {
      'tu',
      'vous',
      'te',
      'toi',
      'ton',
      'ta',
      'tes',
      'votre',
      'vos',
    };
    for (final k in LineKey.values) {
      for (var i = 0; i < 6; i++) {
        final words = bank
            .text(fr, k, params)
            .toLowerCase()
            .split(RegExp(r"[\s.,;:?!'’]+"));
        expect(words.where(banned.contains), isEmpty, reason: '$k');
      }
    }
  });

  test('a key with several variants never repeats immediately', () {
    final bank = LineBank(random: Random(3));
    var last = bank.text(en, LineKey.idleClick);
    for (var i = 0; i < 50; i++) {
      final next = bank.text(en, LineKey.idleClick);
      expect(next, isNot(last));
      last = next;
    }
  });

  test('welcome uses the name, or the anonymous line without one', () {
    final bank = LineBank(random: Random(4));
    expect(
      bank.text(en, LineKey.welcome, {'name': 'Camille'}),
      contains('Camille'),
    );
    expect(bank.text(fr, LineKey.welcome), 'Bienvenue.');
  });

  test('reference lines are present verbatim', () {
    final bank = LineBank(random: Random(5));
    expect(bank.text(fr, LineKey.lock), 'Bien fermé.');
    expect(bank.text(en, LineKey.keyChanged), 'This key changed. Blocking.');
    expect(bank.text(fr, LineKey.night), 'Encore debout ?');
  });

  test('every mood has a label', () {
    for (final m in LoquetMood.values) {
      expect(loquetLabel(en, m), startsWith('Loquet'));
      expect(loquetLabel(fr, m), startsWith('Loquet'));
    }
  });
}
