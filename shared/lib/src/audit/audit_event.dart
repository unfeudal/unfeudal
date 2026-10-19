// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:math';

import '../bytes.dart';
import '../time.dart';
import '../util/json_reader.dart';

/// One link of an audit chain. [ipAddress] is the raw address, served apart and outside the hash.
class AuditEvent {
  const AuditEvent({
    required this.scope,
    required this.seq,
    required this.ts,
    required this.actorUser,
    required this.actorDevice,
    required this.ip,
    required this.action,
    required this.targetIds,
    required this.prevHash,
    required this.hash,
    this.ipAddress,
    this.extra = const {},
  });

  factory AuditEvent.fromJson(Object? json) {
    final r = JsonReader(json, 'auditEvent');
    String nonEmpty(String key) {
      final value = r.text(key, max: 200);
      if (value.isEmpty) throw FormatException('auditEvent.$key: empty');
      return value;
    }

    final ts = r.text('ts', max: 24);
    parseIso(ts); // kept as sent: the hash covers the text
    return AuditEvent(
      scope: nonEmpty('scope'),
      seq: r.integer('seq', min: 1),
      ts: ts,
      actorUser: r.optText('actorUser', max: 200),
      actorDevice: r.optText('actorDevice', max: 200),
      ip: r.optText('ip', max: 200),
      action: nonEmpty('action'),
      targetIds: r.list<String>('targetIds', max: 101),
      prevHash: nonEmpty('prevHash'),
      hash: nonEmpty('hash'),
      ipAddress: r.optText('ipAddress', max: 200),
      extra: r.extra(_known),
    );
  }

  static const _known = {
    'scope',
    'seq',
    'ts',
    'actorUser',
    'actorDevice',
    'ip',
    'action',
    'targetIds',
    'prevHash',
    'hash',
    'ipAddress',
  };

  final String scope;
  final int seq;

  /// The timestamp text as stored; the hash covers it, so it is never reformatted.
  final String ts;
  final String? actorUser;
  final String? actorDevice;

  /// Pseudonym of the address (`ip:<hex>`), inside the hash.
  final String? ip;
  final String action;
  final List<String> targetIds;
  final String prevHash;
  final String hash;
  final String? ipAddress;
  final Map<String, Object?> extra;

  /// What the hash covers: every field but prevHash, hash and ipAddress; nulls kept.
  Map<String, Object?> hashFields() => {
    ...extra,
    'scope': scope,
    'seq': seq,
    'ts': ts,
    'actorUser': actorUser,
    'actorDevice': actorDevice,
    'ip': ip,
    'action': action,
    'targetIds': targetIds,
  };

  Map<String, Object?> toJson() => {
    ...hashFields(),
    'prevHash': prevHash,
    'hash': hash,
    'ipAddress': ?ipAddress,
  };
}

/// Keyset position in an audit listing: `b64(utf8(json{t, s, q}))`.
class AuditCursor {
  const AuditCursor({required this.t, required this.s, required this.q});

  /// Any undecodable or out-of-range cursor is a [FormatException].
  factory AuditCursor.decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(unb64(text)));
    } on Exception {
      throw const FormatException('auditCursor: malformed');
    }
    final r = JsonReader(json, 'auditCursor');
    final t = r.text('t', max: 24);
    parseIso(t);
    final s = r.text('s', max: 200);
    if (s.isEmpty) throw const FormatException('auditCursor.s: empty');
    return AuditCursor(t: t, s: s, q: r.integer('q'));
  }

  final String t;
  final String s;
  final int q;

  String encode() => b64(utf8.encode(jsonEncode({'t': t, 's': s, 'q': q})));
}

/// The retention that applies: the server value unless the org sets a stricter one (0: keep forever).
int effectiveRetention(int server, int? org) => org == null
    ? server
    : server == 0
    ? org
    : min(server, org);
