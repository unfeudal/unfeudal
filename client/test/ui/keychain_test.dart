// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/keys/key_tools.dart';
import 'package:unfeudal_client/src/ui/keychain/keychain_screen.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('generate Ed25519 (default) with a passphrase', (t) async {
    final s = await signedInState(t);
    await pumpApp(t, state: s, child: const KeychainScreen());
    await t.tap(find.byKey(const Key('key-generate')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('gen-name')), 'laptop');
    await t.enterText(find.byKey(const Key('gen-passphrase')), 'pp');
    await t.tap(find.byKey(const Key('gen-save')));
    await pumpReal(t, rounds: 40);
    final e = s.vault!.ofKind(ItemKind.identity).single;
    expect(e.meta!['kind'], 'privateKey');
    expect(e.meta!['publicKey'] as String, startsWith('ssh-ed25519 '));
    late IdentitySecret secret;
    await t.runAsync(
      () async => secret = (await s.vault!.identitySecret(e.id))!,
    );
    expect(secret.passphrase, 'pp');
  });

  testWidgets('import validates the key first; PuTTY refused', (t) async {
    final s = await signedInState(t);
    late GeneratedKey k;
    await t.runAsync(() async => k = await generateEd25519());
    await pumpApp(t, state: s, child: const KeychainScreen());
    final l = AppLocalizations.of(t.element(find.byType(KeychainScreen)));
    await t.tap(find.byKey(const Key('key-import')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('import-name')), 'putty');
    await t.enterText(
      find.byKey(const Key('import-pem')),
      'PuTTY-User-Key-File-3: ssh-ed25519',
    );
    await t.tap(find.byKey(const Key('import-save')));
    await pumpReal(t, rounds: 5);
    expect(find.text(l.errorInvalidKey), findsOneWidget);
    await t.enterText(find.byKey(const Key('import-pem')), k.privateKeyPem);
    await t.tap(find.byKey(const Key('import-save')));
    await pumpReal(t, rounds: 10);
    expect(
      s.vault!.ofKind(ItemKind.identity).single.meta!['publicKey'],
      startsWith(k.publicKey.split(' ').take(2).join(' ')),
    );
  });

  testWidgets('password identity; copy public key; rename keeps the secret', (
    t,
  ) async {
    final s = await signedInState(t);
    final clip = <String?>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clip.add((call.arguments as Map)['text'] as String?);
        }
        return null;
      },
    );
    await pumpApp(t, state: s, child: const KeychainScreen());
    await t.tap(find.byKey(const Key('key-password')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('pw-name')), 'root pw');
    await t.enterText(find.byKey(const Key('pw-value')), 's3cret');
    await t.tap(find.byKey(const Key('pw-save')));
    await pumpReal(t, rounds: 10);
    final id = s.vault!.ofKind(ItemKind.identity).single.id;
    await t.tap(find.byKey(Key('identity-rename-$id')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('identity-name')), 'root password');
    await t.tap(find.byKey(const Key('identity-name-save')));
    await pumpReal(t, rounds: 10);
    expect(s.vault!.entry(id)!.name, 'root password');
    late IdentitySecret secret;
    await t.runAsync(() async => secret = (await s.vault!.identitySecret(id))!);
    expect(secret.password, 's3cret');
    expect(
      find.byKey(Key('identity-copy-$id')),
      findsNothing,
    ); // passwords have no public key
    expect(clip, isEmpty);
  });
}
