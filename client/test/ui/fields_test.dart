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
    expect(passwordScore('kqz'), 1);
    expect(passwordScore('kqzmwrvt'), 2);
    expect(passwordScore('kqzmwrvtpbnx'), 3);
    expect(passwordScore('Kqzmwrvt7bnx'), 4);
    expect(passwordScore('kqzmwrvtpbnxhjfd'), 4);
  });

  test('a guessable password of a valid length scores as weak', () {
    for (final guessable in [
      'password123',
      'P@ssw0rd!',
      'motdepasse',
      'azertyuiop',
      'qwerty2024',
      '1234567890',
      'zyxwvutsrq',
      'aaaaaaaaaaaa',
      'abcabcabcabc',
    ]) {
      expect(passwordScore(guessable), 1, reason: guessable);
    }
    expect(passwordScore('kqzmwrvtpb'), greaterThan(1));
  });

  test('password length is counted after NFC normalization', () {
    final l = lookupAppLocalizations(const Locale('en'));
    expect(passwordScore(decomposed), 1);
    expect(checkNewPassword(l, decomposed, decomposed), isNotNull);
  });
}
