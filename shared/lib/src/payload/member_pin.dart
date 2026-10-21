// SPDX-License-Identifier: Apache-2.0
import '../crypto/safety_code.dart';
import '../util/json_reader.dart';
import 'payload.dart';

class MemberPinMeta extends Payload {
  MemberPinMeta({
    super.schemaVersion = Payload.knownSchemaVersion,
    required this.userId,
    required this.fingerprint,
    this.verified = false,
    super.extra = const {},
  });

  factory MemberPinMeta.fromJson(Object? json) {
    final r = JsonReader(json, 'memberPin');
    final fingerprint = r.req<String>('fingerprint');
    if (!isKeyFingerprint(fingerprint)) {
      throw const FormatException('memberPin.fingerprint: invalid');
    }
    return MemberPinMeta(
      schemaVersion: r.integer('schemaVersion', min: 1),
      userId: r.uuid('userId'),
      fingerprint: fingerprint,
      verified: r.flag('verified', orElse: false),
      extra: r.extra(const {
        'schemaVersion',
        'userId',
        'fingerprint',
        'verified',
      }),
    );
  }

  final String userId;
  final String fingerprint;
  final bool verified;

  @override
  Map<String, Object?> toJson() => {
    ...extra,
    'schemaVersion': schemaVersion,
    'userId': userId,
    'fingerprint': fingerprint,
    'verified': verified,
  };
}
