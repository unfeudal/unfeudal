// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/keys/key_tools.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  test(
    'Ed25519: OpenSSH PEM and a one-line public key that round-trips',
    () async {
      final k = await generateEd25519(comment: 'camille@laptop');
      expect(
        k.privateKeyPem,
        startsWith('-----BEGIN OPENSSH PRIVATE KEY-----'),
      );
      expect(
        k.publicKey,
        matches(RegExp(r'^ssh-ed25519 [A-Za-z0-9+/=]+ camille@laptop$')),
      );
      expect(
        publicKeyOf(k.privateKeyPem),
        startsWith(k.publicKey.split(' ').take(2).join(' ')),
      );
      expect(
        IdentityMeta.fromJson({
          'schemaVersion': 1,
          'name': 'k',
          'kind': 'privateKey',
          'publicKey': k.publicKey,
        }).publicKey,
        k.publicKey,
      );
    },
  );

  test('a passphrase encrypts the PEM; a wrong one is InvalidKey; empty means none', () async {
    final k = await generateEd25519(passphrase: 'pp');
    expect(() => publicKeyOf(k.privateKeyPem), throwsA(isA<InvalidKey>()));
    expect(
      () => publicKeyOf(k.privateKeyPem, passphrase: 'no'),
      throwsA(isA<InvalidKey>()),
    );
    expect(
      publicKeyOf(k.privateKeyPem, passphrase: 'pp'),
      startsWith('ssh-ed25519 '),
    );
    final plain = await generateEd25519(passphrase: '');
    expect(publicKeyOf(plain.privateKeyPem), startsWith('ssh-ed25519 '));
  });

  test('RSA with e = 65537', () async {
    // 4096 bits in production; small here for speed.
    final k = await generateRsa4096(bits: 1024);
    // AAAAB3NzaC1yc2EAAAADAQAB encodes the exponent 65537.
    expect(k.publicKey, startsWith('ssh-rsa AAAAB3NzaC1yc2EAAAADAQAB'));
    expect(
      publicKeyOf(k.privateKeyPem).split(' ')[1],
      k.publicKey.split(' ')[1],
    );
  });

  test('PuTTY and garbage are InvalidKey', () {
    expect(
      () =>
          publicKeyOf('PuTTY-User-Key-File-3: ssh-ed25519\nEncryption: none\n'),
      throwsA(isA<InvalidKey>()),
    );
    expect(() => publicKeyOf('hello'), throwsA(isA<InvalidKey>()));
  });
}
