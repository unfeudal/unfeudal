// SPDX-License-Identifier: Apache-2.0
import '../util/json_reader.dart';
import 'payload.dart';

class MemberPinMeta extends Payload {
  MemberPinMeta({
    super.schemaVersion = 1,
    required this.userId,
    required this.fingerprint,
    this.verified = false,
    super.extra = const {},
  });

  factory MemberPinMeta.fromJson(Object? json) {
    final r = JsonReader(json, 'memberPin');
    final fingerprint = r.req<String>('fingerprint');
    if (!_fingerprint.hasMatch(fingerprint)) {
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

  static final _fingerprint = RegExp(r'^[0-9a-f]{40}$');

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
