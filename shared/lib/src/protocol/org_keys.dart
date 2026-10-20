// SPDX-License-Identifier: Apache-2.0
part of 'org_block.dart';

/// One folder key version: a `wrappedKeys` row (the caller's own keys) or a
/// `keyHistory` row; both share one shape.
class WrappedKeyRow {
  WrappedKeyRow({required this.folderId, required this.keys});

  factory WrappedKeyRow.fromJson(Object? json, String what) => WrappedKeyRow(
    folderId: JsonReader(json, what).uuid('folderId'),
    keys: WrappedFolderKeys.fromJson(json),
  );

  final String folderId;
  final WrappedFolderKeys keys; // its extra keeps folderId and unknown fields

  FolderKeyHistory get history => FolderKeyHistory(
    version: keys.version,
    meta: keys.meta,
    secret: keys.secret,
  );

  Map<String, Object?> toJson() => {'folderId': folderId, ...keys.toJson()};
}

/// A member waiting for folder keys; [secret] means they need the secret key.
class KeyRequest {
  KeyRequest({
    required this.orgId,
    required this.folderId,
    required this.userId,
    required this.version,
    required this.secret,
    this.extra = const {},
  });

  factory KeyRequest.fromJson(Object? json) {
    final r = JsonReader(json, 'keyRequest');
    return KeyRequest(
      orgId: r.uuid('orgId'),
      folderId: r.uuid('folderId'),
      userId: r.uuid('userId'),
      version: r.integer('version'),
      secret: r.flag('secret'),
      extra: r.extra(const {
        'orgId',
        'folderId',
        'userId',
        'version',
        'secret',
      }),
    );
  }

  final String orgId;
  final String folderId;
  final String userId;
  final int version;
  final bool secret;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    ...extra,
    'orgId': orgId,
    'folderId': folderId,
    'userId': userId,
    'version': version,
    'secret': secret,
  };
}

class PendingRotation {
  PendingRotation({
    required this.orgId,
    required this.folderId,
    required this.reason,
    required this.removedUserIds,
    this.rotatedVersion,
    this.extra = const {},
  });

  factory PendingRotation.fromJson(Object? json) {
    final r = JsonReader(json, 'pendingRotation');
    return PendingRotation(
      orgId: r.uuid('orgId'),
      folderId: r.uuid('folderId'),
      reason: r.text('reason', max: 64),
      removedUserIds: _uuids(r, 'removedUserIds'),
      rotatedVersion: r.optInteger('rotatedVersion', min: 1),
      extra: r.extra(const {
        'orgId',
        'folderId',
        'reason',
        'removedUserIds',
        'rotatedVersion',
      }),
    );
  }

  final String orgId;
  final String folderId;
  final String reason;
  final List<String> removedUserIds;
  final int? rotatedVersion;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    ...extra,
    'orgId': orgId,
    'folderId': folderId,
    'reason': reason,
    'removedUserIds': removedUserIds,
    'rotatedVersion': rotatedVersion,
  };
}
