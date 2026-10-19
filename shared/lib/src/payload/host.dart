// SPDX-License-Identifier: Apache-2.0
import '../util/json_reader.dart';
import 'payload.dart';

enum IdentityMode { shared, perMember }

class PortForward {
  PortForward({
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
    this.autoStart = false,
    this.allowLowPorts = false,
    this.extra = const {},
  });

  factory PortForward.fromJson(Object? json) {
    final r = JsonReader(json, 'forward');
    final remoteHost = r.text(
      'remoteHost',
      max: PayloadLimits.remoteHost,
      required: true,
    );
    if (RegExp(r'\s').hasMatch(remoteHost)) {
      throw const FormatException('forward.remoteHost: contains whitespace');
    }
    if (r.opt<bool>('allowLowPorts') == false) {
      throw const FormatException('forward.allowLowPorts: true or absent');
    }
    return PortForward(
      localPort: r.integer('localPort', min: 1, max: 65535),
      remoteHost: remoteHost,
      remotePort: r.integer('remotePort', min: 1, max: 65535),
      autoStart: r.flag('autoStart', orElse: false),
      allowLowPorts: r.opt<bool>('allowLowPorts') ?? false,
      extra: r.extra(const {
        'localPort',
        'remoteHost',
        'remotePort',
        'autoStart',
        'allowLowPorts',
      }),
    );
  }

  final int localPort;
  final String remoteHost;
  final int remotePort;
  final bool autoStart;
  final bool allowLowPorts;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    ...extra,
    'localPort': localPort,
    'remoteHost': remoteHost,
    'remotePort': remotePort,
    'autoStart': autoStart,
    if (allowLowPorts) 'allowLowPorts': true,
  };
}

enum ForwardIssueKind { lowPortNotAllowed, duplicateLocalPort }

class ForwardIssue {
  const ForwardIssue(this.index, this.kind);

  final int index;
  final ForwardIssueKind kind;
}

/// Issues per index, in order: a low port without `allowLowPorts`, then a
/// `localPort` already used by an earlier forward.
List<ForwardIssue> validateForwards(List<PortForward> forwards) {
  final issues = <ForwardIssue>[];
  final seen = <int>{};
  for (var i = 0; i < forwards.length; i++) {
    final f = forwards[i];
    if (f.localPort < 1024 && !f.allowLowPorts) {
      issues.add(ForwardIssue(i, ForwardIssueKind.lowPortNotAllowed));
    }
    if (!seen.add(f.localPort)) {
      issues.add(ForwardIssue(i, ForwardIssueKind.duplicateLocalPort));
    }
  }
  return issues;
}

/// `host` meta. Null [port], [user], [identityId] and [jumpHostId] inherit
/// from the folder chain.
class HostMeta extends Payload {
  HostMeta({
    super.schemaVersion = 1,
    required this.name,
    required this.address,
    this.port,
    this.user,
    this.identityId,
    this.identityMode = IdentityMode.shared,
    this.tags = const [],
    this.notes,
    this.startupCommand,
    this.forwards = const [],
    this.jumpHostId,
    super.extra = const {},
  });

  factory HostMeta.fromJson(Object? json) {
    final r = JsonReader(json, 'host');
    final tags = r.optList<String>('tags', max: PayloadLimits.tags);
    if (tags.any((t) => t.runes.length > PayloadLimits.tag)) {
      throw const FormatException('host.tags: tag too long');
    }
    final forwards = [
      for (final f in r.optList<Object>(
        'forwards',
        max: PayloadLimits.forwards,
      ))
        PortForward.fromJson(f),
    ];
    if (validateForwards(forwards).isNotEmpty) {
      throw const FormatException('host.forwards: low port or duplicate');
    }
    final mode = r.opt<String>('identityMode');
    return HostMeta(
      schemaVersion: r.integer('schemaVersion', min: 1),
      name: r.text('name', max: PayloadLimits.name, required: true),
      address: r.text('address', max: PayloadLimits.address, required: true),
      port: r.optInteger('port', min: 1, max: 65535),
      user: r.optText('user', max: PayloadLimits.user),
      identityId: r.optUuid('identityId'),
      identityMode: mode == null
          ? IdentityMode.shared
          : IdentityMode.values.asNameMap()[mode] ??
                (throw const FormatException('host.identityMode: unknown')),
      tags: tags,
      notes: r.optText('notes', max: PayloadLimits.notes),
      startupCommand: r.optText(
        'startupCommand',
        max: PayloadLimits.startupCommand,
      ),
      forwards: forwards,
      jumpHostId: r.optUuid('jumpHostId'),
      extra: r.extra(_known),
    );
  }

  static const _known = {
    'schemaVersion',
    'name',
    'address',
    'port',
    'user',
    'identityId',
    'identityMode',
    'tags',
    'notes',
    'startupCommand',
    'forwards',
    'jumpHostId',
  };

  final String name;
  final String address;
  final int? port;
  final String? user;
  final String? identityId;
  final IdentityMode identityMode;
  final List<String> tags;
  final String? notes;
  final String? startupCommand;
  final List<PortForward> forwards;
  final String? jumpHostId;

  @override
  Map<String, Object?> toJson() => {
    ...extra,
    'schemaVersion': schemaVersion,
    'name': name,
    'address': address,
    if (port != null) 'port': port,
    'user': user,
    'identityId': identityId,
    if (identityMode == IdentityMode.perMember) 'identityMode': 'perMember',
    'tags': tags,
    'notes': notes,
    'startupCommand': startupCommand,
    if (forwards.isNotEmpty) 'forwards': [for (final f in forwards) f.toJson()],
    if (jumpHostId != null) 'jumpHostId': jumpHostId,
  };
}
