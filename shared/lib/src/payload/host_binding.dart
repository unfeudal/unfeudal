// SPDX-License-Identifier: Apache-2.0
import '../util/json_reader.dart';
import 'payload.dart';

/// The caller's own identity for a `perMember` org host.
class HostBindingMeta extends Payload {
  HostBindingMeta({
    super.schemaVersion = Payload.knownSchemaVersion,
    required this.hostItemId,
    required this.identityId,
    super.extra = const {},
  });

  factory HostBindingMeta.fromJson(Object? json) {
    final r = JsonReader(json, 'hostBinding');
    return HostBindingMeta(
      schemaVersion: r.integer('schemaVersion', min: 1),
      hostItemId: r.uuid('hostItemId'),
      identityId: r.uuid('identityId'),
      extra: r.extra(const {'schemaVersion', 'hostItemId', 'identityId'}),
    );
  }

  final String hostItemId;
  final String identityId;

  @override
  Map<String, Object?> toJson() => {
    ...extra,
    'schemaVersion': schemaVersion,
    'hostItemId': hostItemId,
    'identityId': identityId,
  };
}
