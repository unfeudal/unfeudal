// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../config/features.dart';
import '../db/db.dart';
import '../util/clock.dart';

class AuditScope {
  const AuditScope(this.wire);
  final String wire; // instance | user:<id> | org:<id>
  static const instance = AuditScope('instance');
  factory AuditScope.user(String id) => AuditScope('user:$id');
  factory AuditScope.org(String id) => AuditScope('org:$id');

  /// The org of an `org:<id>` chain, else null.
  String? get orgId => wire.startsWith('org:') ? wire.substring(4) : null;
}

class AuditLog {
  AuditLog(this.clock, this.features, List<int> serverSecret)
    : _ipKey = hkdf32(serverSecret, 'unfeudal/audit-ip/v1');
  final Clock clock;
  final Features features;
  final Future<Uint8List> _ipKey;

  Future<String> ipPseudonym(String ip) async =>
      'ip:${Hmac(sha256, await _ipKey).convert(utf8.encode(ip)).toString().substring(0, 32)}';

  /// Inside the caller's transaction. The head row is locked by the UPDATE until commit (both engines),
  /// so concurrent writers of one scope queue and the chain never forks.
  Future<void> append(
    Tx tx, {
    required AuditScope scope,
    required String action,
    String? actorUser,
    String? actorDevice,
    String? ip,
    List<String> targetIds = const [],
  }) async {
    if (!features.enabled(Flag.audit)) return;
    final s = {'s': scope.wire};
    await tx.execute(
      'INSERT INTO audit_heads (scope, seq, hash) VALUES (@s, 0, @g) ON CONFLICT (scope) DO NOTHING',
      {...s, 'g': genesisHash},
    );
    final head = (await tx.query(
      'UPDATE audit_heads SET seq = seq + 1 WHERE scope = @s RETURNING seq, hash',
      s,
    )).single;
    final event = AuditEvent(
      scope: scope.wire,
      seq: head['seq']! as int,
      ts: iso(clock.now()),
      actorUser: actorUser,
      actorDevice: actorDevice,
      ip: ip == null ? null : await ipPseudonym(ip),
      action: action,
      targetIds: targetIds.length <= 100
          ? targetIds
          : [...targetIds.take(100), 'count:${targetIds.length}'],
      prevHash: head['hash']! as String,
      hash: '',
    );
    final hash = auditHash(event.prevHash, event.hashFields());
    await tx.execute(
      'INSERT INTO audit_events (scope, seq, ts, actor_user, actor_device, ip, action, target_ids, prev_hash, hash) '
      'VALUES (@s, @q, @ts, @au, @ad, @ip, @a, @t, @p, @h)',
      {
        ...s,
        'q': event.seq,
        'ts': event.ts,
        'au': actorUser,
        'ad': actorDevice,
        'ip': event.ip,
        'a': action,
        't': jsonEncode(event.targetIds),
        'p': event.prevHash,
        'h': hash,
      },
    );
    await tx.execute('UPDATE audit_heads SET hash = @h WHERE scope = @s', {
      ...s,
      'h': hash,
    });
    if (ip != null) {
      await tx.execute(
        'INSERT INTO audit_ips (scope, seq, ip) VALUES (@s, @q, @ip)',
        {...s, 'q': event.seq, 'ip': ip},
      );
    }
  }
}

AuditEvent eventOfRow(Map<String, Object?> row, {String? ipAddress}) =>
    AuditEvent(
      scope: row['scope']! as String,
      seq: row['seq']! as int,
      ts: row['ts']! as String,
      actorUser: row['actor_user'] as String?,
      actorDevice: row['actor_device'] as String?,
      ip: row['ip'] as String?,
      action: row['action']! as String,
      targetIds: (jsonDecode(row['target_ids']! as String) as List)
          .cast<String>(),
      prevHash: row['prev_hash']! as String,
      hash: row['hash']! as String,
      ipAddress: ipAddress,
    );
