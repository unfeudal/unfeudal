// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/settings/settings.dart';

import 'support/fakes.dart';
import 'support/pump_app.dart';
import 'support/sync_harness.dart';

void main() {
  test(
    'sent at login and on every change; offline changes never throw',
    () async {
      final h = SyncHarness();
      await h.createAccount('owner@example.org', 'password-000');
      await h.createAccount(testEmail, testPassword);
      final s = testAppState(
        harness: h,
        settings: const Settings(locale: 'fr'),
      );
      await s.boot();
      await s.login(
        server: h.baseUrl,
        email: testEmail,
        password: testPassword,
      );
      expect(h.accounts[testEmail]!.locale, 'fr');
      await s.updateSettings(s.settings.copyWith(locale: 'en'));
      expect(h.accounts[testEmail]!.locale, 'en');
      h.offline = true;
      await s.updateSettings(s.settings.copyWith(locale: 'fr'));
      expect(h.accounts[testEmail]!.locale, 'en');
    },
  );
}
