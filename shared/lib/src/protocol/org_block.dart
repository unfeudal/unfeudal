// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import '../bytes.dart';
import '../crypto/envelope.dart';
import '../crypto/folder_keys.dart';
import '../ids.dart';
import '../util/json_reader.dart';

const _maxRows = 100000;

List<T> _rows<T>(JsonReader r, String key, T Function(Object? json) parse) => [
  for (final row in r.list<Object>(key, max: _maxRows)) parse(row),
];

List<String> _uuids(JsonReader r, String key, {int max = _maxRows}) {
  final ids = r.list<String>(key, max: max);
  if (!ids.every(isUuid)) throw FormatException('${r.what}.$key: not UUIDs');
  return ids;
}

/// One org snapshot of `GET /sync`. Every list is required: a missing list
/// is a [FormatException], never "empty", so a broken block cannot delete
/// local org items.
class OrgBlock {
  OrgBlock({
    required this.orgCursor,
    required this.orgs,
    required this.members,
    required this.teams,
    required this.acl,
    required this.folderTree,
    required this.wrappedKeys,
    required this.keyHistory,
    required this.keyRequests,
    required this.pendingRotations,
    required this.itemIds,
    this.extra = const {},
  });

  factory OrgBlock.fromJson(Object? json) {
    final r = JsonReader(json, 'orgBlock');
    return OrgBlock(
      orgCursor: r.integer('orgCursor'),
      orgs: _rows(r, 'orgs', OrgSummary.fromJson),
      members: _rows(r, 'members', OrgMember.fromJson),
      teams: _rows(r, 'teams', OrgTeam.fromJson),
      acl: _rows(r, 'acl', AclRow.fromJson),
      folderTree: _rows(r, 'folderTree', FolderNode.fromJson),
      wrappedKeys: _rows(
        r,
        'wrappedKeys',
        (j) => WrappedKeyRow.fromJson(j, 'wrappedKeys'),
      ),
      keyHistory: _rows(
        r,
        'keyHistory',
        (j) => WrappedKeyRow.fromJson(j, 'keyHistory'),
      ),
      keyRequests: _rows(r, 'keyRequests', KeyRequest.fromJson),
      pendingRotations: _rows(r, 'pendingRotations', PendingRotation.fromJson),
      itemIds: _uuids(r, 'itemIds'),
      extra: r.extra(const {
        'orgCursor',
        'orgs',
        'members',
        'teams',
        'acl',
        'folderTree',
        'wrappedKeys',
        'keyHistory',
        'keyRequests',
        'pendingRotations',
        'itemIds',
      }),
    );
  }

  final int orgCursor;
  final List<OrgSummary> orgs;
  final List<OrgMember> members;
  final List<OrgTeam> teams;
  final List<AclRow> acl;
  final List<FolderNode> folderTree;
  final List<WrappedKeyRow> wrappedKeys;
  final List<WrappedKeyRow> keyHistory;
  final List<KeyRequest> keyRequests;
  final List<PendingRotation> pendingRotations;
  final List<String> itemIds;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    ...extra,
    'orgCursor': orgCursor,
    'orgs': [for (final x in orgs) x.toJson()],
    'members': [for (final x in members) x.toJson()],
    'teams': [for (final x in teams) x.toJson()],
    'acl': [for (final x in acl) x.toJson()],
    'folderTree': [for (final x in folderTree) x.toJson()],
    'wrappedKeys': [for (final x in wrappedKeys) x.toJson()],
    'keyHistory': [for (final x in keyHistory) x.toJson()],
    'keyRequests': [for (final x in keyRequests) x.toJson()],
    'pendingRotations': [for (final x in pendingRotations) x.toJson()],
    'itemIds': itemIds,
  };
}

class OrgSummary {
  OrgSummary({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
    required this.settings,
    this.extra = const {},
  });

  factory OrgSummary.fromJson(Object? json) {
    final r = JsonReader(json, 'org');
    final settings = r.object('settings');
    if (settings.containsKey('mascot') && settings['mascot'] is! bool) {
      throw const FormatException('org.settings.mascot: not a bool');
    }
    return OrgSummary(
      id: r.uuid('id'),
      name: r.text('name', max: 100),
      role: r.text('role', max: 64),
      status: r.text('status', max: 64),
      settings: settings,
      extra: r.extra(const {'id', 'name', 'role', 'status', 'settings'}),
    );
  }

  final String id;
  final String name;
  final String role;
  final String status;

  /// Kept as read.
  final Map<String, Object?> settings;
  final Map<String, Object?> extra;

  bool get mascot => settings['mascot'] != false;

  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'name': name,
    'role': role,
    'status': status,
    'settings': settings,
  };
}

/// [status], [publicKey] and [disabled] are sent to admins only.
class OrgMember {
  OrgMember({
    required this.orgId,
    required this.userId,
    required this.email,
    required this.role,
    this.status,
    this.publicKey,
    this.disabled,
    this.extra = const {},
  });

  factory OrgMember.fromJson(Object? json) {
    final r = JsonReader(json, 'member');
    return OrgMember(
      orgId: r.uuid('orgId'),
      userId: r.uuid('userId'),
      email: r.text('email', max: 254),
      role: r.text('role', max: 64),
      status: r.optText('status', max: 64),
      publicKey: r.opt<String>('publicKey') == null
          ? null
          : r.bytes('publicKey', length: 32),
      disabled: r.opt<bool>('disabled'),
      extra: r.extra(const {
        'orgId',
        'userId',
        'email',
        'role',
        'status',
        'publicKey',
        'disabled',
      }),
    );
  }

  final String orgId;
  final String userId;
  final String email;
  final String role;
  final String? status;
  final Uint8List? publicKey;
  final bool? disabled;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    ...extra,
    'orgId': orgId,
    'userId': userId,
    'email': email,
    'role': role,
    if (status != null) 'status': status,
    if (publicKey != null) 'publicKey': b64(publicKey!),
    if (disabled != null) 'disabled': disabled,
  };
}

class OrgTeam {
  OrgTeam({
    required this.orgId,
    required this.id,
    required this.name,
    required this.memberIds,
    this.extra = const {},
  });

  factory OrgTeam.fromJson(Object? json) {
    final r = JsonReader(json, 'team');
    return OrgTeam(
      orgId: r.uuid('orgId'),
      id: r.uuid('id'),
      name: r.text('name', max: 100),
      memberIds: _uuids(r, 'memberIds', max: 500),
      extra: r.extra(const {'orgId', 'id', 'name', 'memberIds'}),
    );
  }

  final String orgId;
  final String id;
  final String name;
  final List<String> memberIds;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    ...extra,
    'orgId': orgId,
    'id': id,
    'name': name,
    'memberIds': memberIds,
  };
}

class AclRow {
  AclRow({
    required this.orgId,
    required this.folderId,
    required this.principalType,
    required this.principalId,
    required this.allow,
    required this.deny,
    this.extra = const {},
  });

  factory AclRow.fromJson(Object? json) {
    final r = JsonReader(json, 'acl');
    return AclRow(
      orgId: r.uuid('orgId'),
      folderId: r.uuid('folderId'),
      principalType: r.text('principalType', max: 64),
      principalId: r.uuid('principalId'),
      allow: r.list<String>('allow', max: 5),
      deny: r.list<String>('deny', max: 5),
      extra: r.extra(const {
        'orgId',
        'folderId',
        'principalType',
        'principalId',
        'allow',
        'deny',
      }),
    );
  }

  final String orgId;
  final String folderId;
  final String principalType;
  final String principalId;
  final List<String> allow;
  final List<String> deny;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    ...extra,
    'orgId': orgId,
    'folderId': folderId,
    'principalType': principalType,
    'principalId': principalId,
    'allow': allow,
    'deny': deny,
  };
}

class FolderNode {
  FolderNode({
    required this.orgId,
    required this.folderId,
    this.parentId,
    this.extra = const {},
  });

  factory FolderNode.fromJson(Object? json) {
    final r = JsonReader(json, 'folderTree');
    return FolderNode(
      orgId: r.uuid('orgId'),
      folderId: r.uuid('folderId'),
      parentId: r.optUuid('parentId'),
      extra: r.extra(const {'orgId', 'folderId', 'parentId'}),
    );
  }

  final String orgId;
  final String folderId;
  final String? parentId;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    ...extra,
    'orgId': orgId,
    'folderId': folderId,
    'parentId': parentId,
  };
}

/// One folder key version: a `wrappedKeys` row (the caller's own keys) or a
/// `keyHistory` row; both share one shape.
class WrappedKeyRow {
  WrappedKeyRow({
    required this.folderId,
    required this.version,
    required this.meta,
    this.secret,
    this.extra = const {},
  });

  factory WrappedKeyRow.fromJson(Object? json, String what) {
    final r = JsonReader(json, what);
    final secret = r.opt<Map<String, Object?>>('secret');
    return WrappedKeyRow(
      folderId: r.uuid('folderId'),
      version: r.integer('version', min: 1),
      meta: Envelope.fromJson(r.object('meta')),
      secret: secret == null ? null : Envelope.fromJson(secret),
      extra: r.extra(const {'folderId', 'version', 'meta', 'secret'}),
    );
  }

  final String folderId;
  final int version;
  final Envelope meta;
  final Envelope? secret;
  final Map<String, Object?> extra;

  WrappedFolderKeys get keys =>
      WrappedFolderKeys(version: version, meta: meta, secret: secret);

  FolderKeyHistory get history =>
      FolderKeyHistory(version: version, meta: meta, secret: secret);

  Map<String, Object?> toJson() => {
    ...extra,
    'folderId': folderId,
    'version': version,
    'meta': meta.toJson(),
    'secret': secret?.toJson(),
  };
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
