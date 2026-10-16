// SPDX-License-Identifier: Apache-2.0
import '../util/json_reader.dart';
import 'payload.dart';

/// A pinned SSH host key. The local ledger's pins win over this synced copy.
class KnownHostMeta extends Payload {
  KnownHostMeta({
    super.schemaVersion = 1,
    required this.hostItemId,
    required this.keyType,
    required this.sha256Fingerprint,
    super.extra = const {},
  });

  factory KnownHostMeta.fromJson(Object? json) {
    final r = JsonReader(json, 'knownHost');
    final fingerprint = r.req<String>('sha256Fingerprint');
    if (!_fingerprint.hasMatch(fingerprint)) {
      throw const FormatException('knownHost.sha256Fingerprint: invalid');
    }
    return KnownHostMeta(
      schemaVersion: r.integer('schemaVersion', min: 1),
      hostItemId: r.uuid('hostItemId'),
      keyType: r.text('keyType', max: PayloadLimits.keyType, required: true),
      sha256Fingerprint: fingerprint,
      extra: r.extra(const {
        'schemaVersion',
        'hostItemId',
        'keyType',
        'sha256Fingerprint',
      }),
    );
  }

  static final _fingerprint = RegExp(r'^SHA256:[A-Za-z0-9+/]{43}$');

  final String hostItemId;
  final String keyType;
  final String sha256Fingerprint;

  @override
  Map<String, Object?> toJson() => {
    ...extra,
    'schemaVersion': schemaVersion,
    'hostItemId': hostItemId,
    'keyType': keyType,
    'sha256Fingerprint': sha256Fingerprint,
  };
}
