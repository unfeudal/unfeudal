// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/ui/keychain/keychain_screen.dart';

import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  Future<(SyncHarness, String)> open(WidgetTester t, List<String> caps) async {
    final h = SyncHarness(capabilities: caps);
    final s = await signedInState(t, harness: h);
    late String id;
    await t.runAsync(
      () async => id = await s.vault!.upsertItem(
        type: 'identity',
        meta: {
          'schemaVersion': 1,
          'name': 'root',
          'kind': 'password',
          'publicKey': null,
        },
        secret: {
          'schemaVersion': 1,
          'kind': 'password',
          'privateKeyPem': null,
          'passphrase': null,
          'password': 's3cret',
        },
      ),
    );
    await pumpApp(t, state: s, child: const KeychainScreen());
    await pumpReal(t);
    return (h, id);
  }

  testWidgets('with the reveal flag: shows the secret and reports it', (
    t,
  ) async {
    final (h, id) = await open(t, ['client_events', 'reveal', 'sync']);
    expect(find.text('s3cret'), findsNothing);
    await t.tap(find.byKey(Key('identity-reveal-$id')));
    await pumpReal(t);
    expect(find.text('s3cret'), findsOneWidget);
    expect(h.reported.map((r) => r.body).toList(), [
      {'itemId': id},
    ]);
  });

  testWidgets('without it: no button', (t) async {
    final (_, id) = await open(t, ['client_events', 'sync']);
    expect(find.byKey(Key('identity-reveal-$id')), findsNothing);
  });
}
