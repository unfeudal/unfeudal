// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:pointycastle/export.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

/// Not a private key this app can read: wrong passphrase, PuTTY `.ppk`, or anything else.
class InvalidKey implements Exception {
  const InvalidKey();

  @override
  String toString() => 'InvalidKey';
}

/// [privateKeyPem]: OpenSSH private key, encrypted when a passphrase was given.
/// [publicKey]: one OpenSSH line, `type base64 comment`.
typedef GeneratedKey = ({String privateKeyPem, String publicKey});

const rsaBits = 4096;

Future<GeneratedKey> generateEd25519({
  String comment = '',
  String? passphrase,
}) async {
  final pair = await Ed25519().newKeyPair();
  final seed = await pair.extractPrivateKeyBytes();
  final public = (await pair.extractPublicKey()).bytes;
  return _generated(
    OpenSSHEd25519KeyPair(
      Uint8List.fromList(public),
      Uint8List.fromList([...seed, ...public]),
      comment,
    ),
    comment,
    passphrase,
  );
}

/// e = 65537; generated in a background isolate (several seconds at 4096 bits).
Future<GeneratedKey> generateRsa({
  String comment = '',
  String? passphrase,
  int bits = rsaBits,
}) async {
  final [n, e, d, iqmp, p, q] = await Isolate.run(() => _rsaParts(bits));
  return _generated(
    OpenSSHRsaKeyPair(n, e, d, iqmp, p, q, comment),
    comment,
    passphrase,
  );
}

/// `type base64` of the first key in an OpenSSH or PEM private key file. An empty passphrase means none.
String publicKeyOf(String pem, {String? passphrase}) {
  try {
    return _publicLine(
      SSHKeyPair.fromPem(
        pem,
        passphrase == null || passphrase.isEmpty ? null : passphrase,
      ).first,
    );
  } on Object catch (_) {
    // The parser throws assorted errors; all mean the same thing to the user.
    throw const InvalidKey();
  }
}

GeneratedKey _generated(
  OpenSSHKeyPair pair,
  String comment,
  String? passphrase,
) {
  final line = _publicLine(pair);
  return (
    privateKeyPem: pair.toPem(passphrase: passphrase),
    publicKey: comment.isEmpty ? line : '$line $comment',
  );
}

String _publicLine(SSHKeyPair pair) =>
    '${pair.name} ${base64.encode(pair.toPublicKey().encode())}';

List<BigInt> _rsaParts(int bits) {
  final random = FortunaRandom()..seed(KeyParameter(secureBytes(32)));
  final generator = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64),
        random,
      ),
    );
  final pair = generator.generateKeyPair();
  final public = pair.publicKey;
  final private = pair.privateKey;
  final p = private.p!, q = private.q!;
  return [
    public.modulus!,
    public.publicExponent!,
    private.privateExponent!,
    q.modInverse(p),
    p,
    q,
  ];
}
