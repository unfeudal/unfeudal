// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:unfeudal_server/src/audit/audit_log.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/audit.dart';
import '../support/test_server.dart';

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  late TestServer s;
  setUp(() async => s = await TestServer.start());
  tearDown(() => s.close());

  Future<void> append(
    String action, {
    AuditScope scope = AuditScope.instance,
    String? ip,
    List<String> targets = const [],
  }) => s.db.transaction(
    (tx) => s.deps.audit.append(
      tx,
      scope: scope,
      action: action,
      ip: ip,
      targetIds: targets,
    ),
  );

  test(
    'append chains events from genesis; the head follows; ts is server time',
    () async {
      await append('a');
      s.clock.advance(const Duration(seconds: 1));
      await append('b', targets: ['x']);
      final events = await auditEvents(s, 'instance');
      expect(events.map((e) => [e.seq, e.action, e.ts]), [
        [1, 'a', '2026-10-13T12:00:00.000Z'],
        [2, 'b', '2026-10-13T12:00:01.000Z'],
      ]);
      expect(events.first.prevHash, genesisHash);
      expect(verifyChain(events), isNull);
      final head = (await s.db.query(
        "SELECT seq, hash FROM audit_heads WHERE scope = 'instance'",
      )).single;
      expect([head['seq'], head['hash']], [2, events.last.hash]);
    },
  );

  test('scopes are separate chains', () async {
    await append('a', scope: AuditScope.user('u1'));
    await append('b', scope: AuditScope.org('o1'));
    await append('c', scope: AuditScope.user('u1'));
    expect((await auditEvents(s, 'user:u1')).map((e) => e.seq), [1, 2]);
    expect((await auditEvents(s, 'org:o1')).single.seq, 1);
  });

  test('ip: keyed pseudonym in the chain, raw address apart', () async {
    await append('a', ip: '203.0.113.7');
    await append('b');
    final key = await hkdf32(s.deps.serverSecret, 'unfeudal/audit-ip/v1');
    final expected =
        'ip:${hex(Hmac(sha256, key).convert(utf8.encode('203.0.113.7')).bytes.sublist(0, 16))}';
    final [a, b] = await auditEvents(s, 'instance');
    expect(
      [a.ip, a.ipAddress, b.ip, b.ipAddress],
      [expected, '203.0.113.7', null, null],
    );
    expect(await s.deps.audit.ipPseudonym('203.0.113.7'), expected);
    expect(await s.db.query('SELECT seq FROM audit_ips'), [
      {'seq': 1},
    ]);
  });

  test('targetIds: at most 100 ids, then count:<n>', () async {
    final ids = [for (var i = 0; i < 101; i++) 'id$i'];
    await append('big', targets: ids);
    await append('exact', targets: ids.take(100).toList());
    final [big, exact] = await auditEvents(s, 'instance');
    expect(big.targetIds, [...ids.take(100), 'count:101']);
    expect(exact.targetIds, ids.take(100).toList());
  });

  test('a rolled-back transaction leaves no event and no head', () async {
    await expectLater(
      s.db.transaction((tx) async {
        await s.deps.audit.append(tx, scope: AuditScope.instance, action: 'a');
        throw StateError('rollback');
      }),
      throwsStateError,
    );
    expect(
      (await s.db.query('SELECT count(*) AS n FROM audit_events')).single['n'],
      0,
    );
    expect(await s.db.query('SELECT scope FROM audit_heads'), isEmpty);
  });

  test(
    'concurrent appends on one scope get seq 1..20 without gap and verify',
    () async {
      await Future.wait([
        for (var i = 0; i < 20; i++) append('a$i', ip: '198.51.100.$i'),
      ]);
      final events = await auditEvents(s, 'instance');
      expect(events.map((e) => e.seq), [for (var i = 1; i <= 20; i++) i]);
      expect(verifyChain(events), isNull);
    },
  );

  test('feature audit off writes nothing', () async {
    final off = await TestServer.start(
      env: {'UNFEUDAL_FEATURE_AUDIT': 'false'},
    );
    await off.db.transaction(
      (tx) => off.deps.audit.append(
        tx,
        scope: AuditScope.instance,
        action: 'a',
        ip: '203.0.113.7',
      ),
    );
    for (final t in ['audit_events', 'audit_heads', 'audit_ips']) {
      expect(
        (await off.db.query('SELECT count(*) AS n FROM $t')).single['n'],
        0,
        reason: t,
      );
    }
    await off.close();
  });
}
