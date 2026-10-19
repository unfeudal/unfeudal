// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/audit/audit_log.dart';
import 'package:unfeudal_server/src/audit/retention.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/audit.dart';
import '../support/items.dart';
import '../support/test_server.dart';

void main() {
  late TestServer s;
  setUp(
    () async => s = await TestServer.start(
      env: {
        'UNFEUDAL_AUDIT_RETENTION_DAYS': '60',
        'UNFEUDAL_AUDIT_IP_RETENTION_DAYS': '7',
      },
    ),
  );
  tearDown(() => s.close());

  Future<void> append(
    TestServer on,
    AuditScope scope,
    String action, {
    String? ip,
  }) => on.db.transaction(
    (tx) => on.deps.audit.append(tx, scope: scope, action: action, ip: ip),
  );

  test('audit purge deletes up to the newest old event and appends a checkpoint; the rest verifies', () async {
    for (var i = 0; i < 3; i++) {
      await append(s, AuditScope.instance, 'old$i', ip: '203.0.113.7');
    }
    final old = await auditEvents(s, 'instance');
    s.clock.advance(const Duration(days: 61));
    await append(s, AuditScope.instance, 'new', ip: '203.0.113.8');
    await RetentionJob(s.deps).runOnce();
    final kept = await auditEvents(s, 'instance');
    expect(
      [
        for (final e in kept) [e.seq, e.action, ...e.targetIds],
      ],
      [
        [4, 'new'],
        [5, 'audit.checkpoint', 'seq:3', 'hash:${old.last.hash}'],
      ],
    );
    expect([verifyChain(kept).ok, kept.last.actorUser], [true, null]);
    expect(
      (await s.db.query('SELECT seq FROM audit_ips')).map((r) => r['seq']),
      [4],
    );
    await RetentionJob(s.deps).runOnce();
    expect(
      await auditEvents(s, 'instance'),
      hasLength(2),
      reason: 'nothing old left, no second checkpoint',
    );
  });

  test(
    'an org chain uses the org value; a deleted org follows the instance value',
    () async {
      final (live, gone) = (newId(), newId());
      await s.db.execute(
        'INSERT INTO orgs (id, name, settings, created_at) VALUES (@o, @n, @st, @t)',
        {
          'o': live,
          'n': 'A',
          'st': '{"auditDays":30}',
          't': iso(s.clock.now()),
        },
      );
      await append(s, AuditScope.org(live), 'old');
      await append(s, AuditScope.org(gone), 'old');
      s.clock.advance(const Duration(days: 31));
      await RetentionJob(s.deps).runOnce();
      expect(
        [
          (await actions(s, 'org:$live')).map((a) => a.first),
          (await actions(s, 'org:$gone')).map((a) => a.first),
        ],
        [
          ['audit.checkpoint'],
          ['old'],
        ],
      );
      s.clock.advance(const Duration(days: 30));
      await RetentionJob(s.deps).runOnce();
      expect((await actions(s, 'org:$gone')).map((a) => a.first), [
        'audit.checkpoint',
      ]);
    },
  );

  test('0 keeps events forever; audit off leaves chains alone', () async {
    for (final env in [
      {'UNFEUDAL_AUDIT_RETENTION_DAYS': '0'},
      {
        'UNFEUDAL_FEATURE_AUDIT': 'false',
        'UNFEUDAL_AUDIT_RETENTION_DAYS': '30',
      },
    ]) {
      final other = await TestServer.start(env: env);
      await other.db.execute(
        "INSERT INTO audit_events (scope, seq, ts, action, target_ids, prev_hash, hash) "
        "VALUES ('instance', 1, @t, 'a', '[]', @g, 'h')",
        {'t': iso(other.clock.now()), 'g': genesisHash},
      );
      await other.db.execute(
        "INSERT INTO audit_heads (scope, seq, hash) VALUES ('instance', 1, 'h')",
      );
      other.clock.advance(const Duration(days: 3650));
      await RetentionJob(other.deps).runOnce();
      expect(await actions(other, 'instance'), [
        ['a'],
      ], reason: '$env');
      await other.close();
    }
  });

  test('raw IPs older than audit_ip_retention_days go; the event and its pseudonym stay', () async {
    await append(s, AuditScope.instance, 'a', ip: '203.0.113.7');
    s.clock.advance(const Duration(days: 8));
    await RetentionJob(s.deps).runOnce();
    final e = (await auditEvents(s, 'instance')).single;
    expect([e.ipAddress, e.ip!.startsWith('ip:')], [null, true]);
  });

  test('revisions beyond the effective maxVersions are deleted', () async {
    final h = await TestServer.start(
      env: {'UNFEUDAL_ITEM_HISTORY_MAX_VERSIONS': '2'},
    );
    final o = await h.setupOwner();
    final item = await testItem(o);
    await h.put(
      '/api/v1/items/${item['id']}',
      token: o.accessToken,
      body: item,
      headers: {'if-match': '0'},
    );
    for (var rev = 10; rev < 14; rev++) {
      await h.db.execute(
        "INSERT INTO item_revisions (item_id, revision, body, size, created_at) VALUES (@i, @r, '{}', 2, @t)",
        {'i': item['id'], 'r': rev, 't': iso(h.clock.now())},
      );
    }
    await RetentionJob(h.deps).runOnce();
    expect(
      (await h.db.query(
        'SELECT revision FROM item_revisions ORDER BY revision',
      )).map((r) => r['revision']),
      [12, 13],
    );
    await h.close();
  });
}
