// SPDX-License-Identifier: Apache-2.0
import '../util/json_reader.dart';
import 'payload.dart';

/// Values inherited by the hosts of a folder; null means not set here.
class FolderDefaults {
  const FolderDefaults({
    this.port,
    this.user,
    this.identityId,
    this.jumpHostId,
    this.extra = const {},
  });

  factory FolderDefaults.fromJson(Object? json) {
    final r = JsonReader(json, 'folder.defaults');
    return FolderDefaults(
      port: r.optInteger('port', min: 1, max: 65535),
      user: r.optText('user', max: PayloadLimits.user),
      identityId: r.optUuid('identityId'),
      jumpHostId: r.optUuid('jumpHostId'),
      extra: r.extra(const {'port', 'user', 'identityId', 'jumpHostId'}),
    );
  }

  final int? port;
  final String? user;
  final String? identityId;
  final String? jumpHostId;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    ...extra,
    'port': port,
    'user': user,
    'identityId': identityId,
    if (jumpHostId != null) 'jumpHostId': jumpHostId,
  };
}

class FolderMeta extends Payload {
  FolderMeta({
    super.schemaVersion = 1,
    required this.name,
    this.defaults = const FolderDefaults(),
    super.extra = const {},
  });

  factory FolderMeta.fromJson(Object? json) {
    final r = JsonReader(json, 'folder');
    return FolderMeta(
      schemaVersion: r.integer('schemaVersion', min: 1),
      name: r.text('name', max: PayloadLimits.name, required: true),
      defaults: FolderDefaults.fromJson(r.object('defaults')),
      extra: r.extra(const {'schemaVersion', 'name', 'defaults'}),
    );
  }

  final String name;
  final FolderDefaults defaults;

  @override
  Map<String, Object?> toJson() => {
    ...extra,
    'schemaVersion': schemaVersion,
    'name': name,
    'defaults': defaults.toJson(),
  };
}
