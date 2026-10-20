// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/version.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  const banned = [
    'firebase',
    'sentry',
    'crashlytics',
    'analytics',
    'amplitude',
    'mixpanel',
    'segment',
    'posthog',
    'datadog',
    'bugsnag',
    'appcenter',
    'rollbar',
    'newrelic',
    'appsflyer',
    'telemetry',
    'google_fonts',
  ];

  test('no analytics, crash-reporting or font-fetching package, transitive ones included', () {
    final names = RegExp(
      r'^  ([a-z0-9_]+):$',
      multiLine: true,
    ).allMatches(File('pubspec.lock').readAsStringSync()).map((m) => m[1]!);
    expect(names.where((n) => banned.any(n.contains)), isEmpty);
  });

  test('no URL in lib/ but the compiled release link; no font fetching', () {
    final url = RegExp(r'''https?://[^\s'"]+''');
    // An XML name, never fetched.
    const svgNamespace = 'http://www.w3.org/2000/svg';
    final offenders = <String>[];
    for (final f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final text = f.readAsStringSync();
      final isVersion = f.path.replaceAll(r'\', '/') == 'lib/src/version.dart';
      for (final m in url.allMatches(text)) {
        if (m[0] != svgNamespace &&
            !(isVersion && m[0] == officialReleasesUrl)) {
          offenders.add('${f.path}: ${m[0]}');
        }
      }
      if (text.contains('GoogleFonts') || text.contains('PdfGoogleFonts')) {
        offenders.add('${f.path}: font fetching');
      }
    }
    expect(offenders, isEmpty);
  });

  test('a whole session talks to the server only', () async {
    final h = SyncHarness();
    await h.createAccount(testEmail, testPassword);
    final s = testAppState(harness: h);
    await s.boot();
    await s.login(server: h.baseUrl, email: testEmail, password: testPassword);
    await s.vault!.upsertItem(
      type: 'host',
      meta: hostJson('web', user: 'root'),
    );
    await s.sync!.syncNow();
    await s.api!.devices();
    await s.lock();
    await s.unlock(testPassword);
    await s.sync!.syncNow();
    expect(h.hosts, {'vault.test'});
  });
}
