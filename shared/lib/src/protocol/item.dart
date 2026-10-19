// SPDX-License-Identifier: Apache-2.0
import '../crypto/envelope.dart';
import '../time.dart';
import '../util/json_reader.dart';

enum ItemScope { personal, org }

enum ItemKind {
  host,
  identity,
  folder,
  snippet,
  knownHost,
  profile,
  hostBinding,
  memberPin,
  unknown;

  static ItemKind fromType(String type) => values.asNameMap()[type] ?? unknown;
}

const personalOnlyTypes = {'knownHost', 'profile', 'hostBinding', 'memberPin'};

/// One synced record: ids and placement in clear, content in [meta] and
/// [secret]. Server-set fields are null in a client request body.
class Item {
  Item({
    required this.id,
    required this.type,
    required this.scope,
    required this.orgId,
    required this.folderId,
    this.schemaVersion = 1,
    this.revision,
    this.deleted = false,
    this.purged = false,
    required this.meta,
    required this.secret,
    this.createdAt,
    this.updatedAt,
    this.updatedBy,
    this.updatedDevice,
    this.extra = const {},
  });

  factory Item.fromJson(Object? json) {
    final r = JsonReader(json, 'item');
    final type = r.text('type', max: 64);
    if (type.isEmpty) throw const FormatException('item.type: empty');
    final scope =
        ItemScope.values.asNameMap()[r.req<String>('scope')] ??
        (throw const FormatException('item.scope: unknown'));
    final orgId = r.optUuid('orgId');
    if ((scope == ItemScope.org) != (orgId != null)) {
      throw const FormatException('item.orgId: set iff scope is org');
    }
    final purged = r.opt<bool>('purged');
    if (purged == false) {
      throw const FormatException('item.purged: true or absent');
    }
    final isPurged = purged ?? false;
    final metaJson = r.opt<Map<String, Object?>>('meta');
    final secretJson = r.opt<Map<String, Object?>>('secret');
    if (isPurged && (metaJson != null || secretJson != null)) {
      throw const FormatException('item: a purged item has no payload');
    }
    if (!isPurged && metaJson == null) {
      throw const FormatException('item.meta: missing');
    }
    return Item(
      id: r.uuid('id'),
      type: type,
      scope: scope,
      orgId: orgId,
      folderId: r.optUuid('folderId'),
      schemaVersion: r.integer('schemaVersion', min: 1),
      revision: r.optInteger('revision'),
      deleted: r.flag('deleted'),
      purged: isPurged,
      meta: metaJson == null ? null : Envelope.fromJson(metaJson),
      secret: secretJson == null ? null : Envelope.fromJson(secretJson),
      createdAt: r.optTime('createdAt'),
      updatedAt: r.optTime('updatedAt'),
      updatedBy: r.optUuid('updatedBy'),
      updatedDevice: r.optUuid('updatedDevice'),
      extra: r.extra(_known),
    );
  }

  static const _known = {
    'id',
    'type',
    'scope',
    'orgId',
    'folderId',
    'schemaVersion',
    'revision',
    'deleted',
    'purged',
    'meta',
    'secret',
    'createdAt',
    'updatedAt',
    'updatedBy',
    'updatedDevice',
  };

  final String id;
  final String type;
  final ItemScope scope;
  final String? orgId;
  final String? folderId;
  final int schemaVersion;
  final int? revision;
  final bool deleted;
  final bool purged;
  final Envelope? meta;
  final Envelope? secret;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String? updatedDevice;
  final Map<String, Object?> extra;

  ItemKind get kind => ItemKind.fromType(type);

  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'type': type,
    'scope': scope.name,
    'orgId': orgId,
    'folderId': folderId,
    'schemaVersion': schemaVersion,
    if (revision != null) 'revision': revision,
    'deleted': deleted,
    if (purged) 'purged': true,
    'meta': meta?.toJson(),
    'secret': secret?.toJson(),
    if (createdAt != null) 'createdAt': iso(createdAt!),
    if (updatedAt != null) 'updatedAt': iso(updatedAt!),
    if (updatedBy != null) 'updatedBy': updatedBy,
    if (updatedDevice != null) 'updatedDevice': updatedDevice,
  };
}
