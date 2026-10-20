// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/ui/fields.dart';
import 'package:unfeudal_client/src/ui/onboarding/setup_screen.dart';

void main() {
  // 8 runes as typed, 4 once NFC-normalized as the account crypto counts them
  final decomposed = 'é' * 4;

  test('password score: empty, short, then length and character classes', () {
    expect(passwordScore(''), 0);
    expect(passwordScore('abc'), 1);
    expect(passwordScore('abcdefgh'), 2);
    expect(passwordScore('abcdefghijkl'), 3);
    expect(passwordScore('Abcdefgh1jkl'), 4);
    expect(passwordScore('abcdefghijklmnop'), 4);
  });

  test('password length is counted after NFC normalization', () {
    final l = lookupAppLocalizations(const Locale('en'));
    expect(passwordScore(decomposed), 1);
    expect(checkNewPassword(l, decomposed, decomposed), isNotNull);
  });
}
