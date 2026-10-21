// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/ui/onboarding/setup_screen.dart';

void main() {
  test('a new password is checked after NFC normalization', () {
    // 8 runes as typed, 4 once NFC-normalized as the account crypto counts them
    final decomposed = 'é' * 4;
    final l = lookupAppLocalizations(const Locale('en'));
    expect(checkNewPassword(l, decomposed, decomposed), isNotNull);
  });
}
