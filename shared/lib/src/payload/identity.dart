// SPDX-License-Identifier: Apache-2.0
import '../util/json_reader.dart';
import 'payload.dart';

enum IdentityKind { privateKey, password }

IdentityKind _readKind(JsonReader r) =>
    IdentityKind.values.asNameMap()[r.req<String>('kind')] ??
    (throw FormatException('${r.what}.kind: unknown'));

class IdentityMeta extends Payload {
  IdentityMeta({
    super.schemaVersion = 1,
    required this.name,
    required this.kind,
    this.publicKey,
    super.extra = const {},
  });

  factory IdentityMeta.fromJson(Object? json) {
    final r = JsonReader(json, 'identity');
    final publicKey = r.optText('publicKey', max: PayloadLimits.sshKeyText);
    if (publicKey != null && !_openSshLine.hasMatch(publicKey)) {
      throw const FormatException('identity.publicKey: not one OpenSSH line');
    }
    return IdentityMeta(
      schemaVersion: r.integer('schemaVersion', min: 1),
      name: r.text('name', max: PayloadLimits.name, required: true),
      kind: _readKind(r),
      publicKey: publicKey,
      extra: r.extra(const {'schemaVersion', 'name', 'kind', 'publicKey'}),
    );
  }

  /// `type base64 [comment]` on a single line.
  static final _openSshLine = RegExp(r'^\S+ \S+( [^\r\n]*)?$');

  final String name;
  final IdentityKind kind;
  final String? publicKey;

  @override
  Map<String, Object?> toJson() => {
    ...extra,
    'schemaVersion': schemaVersion,
    'name': name,
    'kind': kind.name,
    'publicKey': publicKey,
  };
}

/// Meta and secret `kind` equality is checked by the caller that opened both.
class IdentitySecret extends Payload {
  IdentitySecret({
    super.schemaVersion = 1,
    required this.kind,
    this.privateKeyPem,
    this.passphrase,
    this.password,
    super.extra = const {},
  });

  factory IdentitySecret.fromJson(Object? json) {
    final r = JsonReader(json, 'identitySecret');
    final kind = _readKind(r);
    final privateKeyPem = r.optText(
      'privateKeyPem',
      max: PayloadLimits.sshKeyText,
    );
    final password = r.optText('password', max: PayloadLimits.secretText);
    if (kind == IdentityKind.privateKey && privateKeyPem == null) {
      throw const FormatException('identitySecret.privateKeyPem: missing');
    }
    if (kind == IdentityKind.password && password == null) {
      throw const FormatException('identitySecret.password: missing');
    }
    return IdentitySecret(
      schemaVersion: r.integer('schemaVersion', min: 1),
      kind: kind,
      privateKeyPem: privateKeyPem,
      passphrase: r.optText('passphrase', max: PayloadLimits.secretText),
      password: password,
      extra: r.extra(const {
        'schemaVersion',
        'kind',
        'privateKeyPem',
        'passphrase',
        'password',
      }),
    );
  }

  final IdentityKind kind;
  final String? privateKeyPem;
  final String? passphrase;
  final String? password;

  @override
  Map<String, Object?> toJson() => {
    ...extra,
    'schemaVersion': schemaVersion,
    'kind': kind.name,
    'privateKeyPem': privateKeyPem,
    'passphrase': passphrase,
    'password': password,
  };
}
