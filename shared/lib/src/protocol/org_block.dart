// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import '../bytes.dart';
import '../crypto/folder_keys.dart';
import '../ids.dart';
import '../permissions/resolver.dart';
import '../util/json_reader.dart';

part 'org_keys.dart';

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

  /// Null for a role this build does not know.
  OrgRole? get knownRole => OrgRole.values.asNameMap()[role];

  bool get isMascotEnabled => settings['mascot'] != false;

  bool get isConfirmed => status == MemberStatus.confirmed.name;

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

  /// Null for a role this build does not know.
  OrgRole? get knownRole => OrgRole.values.asNameMap()[role];

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

  bool get isTeam => principalType == PrincipalType.team.name;

  /// Typed for the resolver; unknown permission names are skipped and any
  /// principal type other than team reads as user.
  AclEntry get entry => AclEntry(
    folderId: folderId,
    principalType: isTeam ? PrincipalType.team : PrincipalType.user,
    principalId: principalId,
    allow: _permissions(allow),
    deny: _permissions(deny),
  );

  static Set<Permission> _permissions(List<String> names) => {
    for (final name in names) ?Permission.values.asNameMap()[name],
  };

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
