// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/audit/audit_anchors.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/sync_harness.dart';

void main() {
  late SyncHarness h;
  late LocalMirror mirror;
  late AuditAnchors anchors;
  setUp(() {
    h = SyncHarness();
    mirror = LocalMirror.inMemory();
    anchors = AuditAnchors(mirror);
  });

  List<AuditEvent> chain(String scope) =>
      h.auditLog.where((e) => e.scope == scope).toList();
  void events(int n, [String scope = 'instance']) {
    for (var i = 0; i < n; i++) {
      h.appendAudit(scope, 'device.added');
    }
  }

  List<List<Object?>> shape(List<AnchorAlert> alerts) => [
    for (final a in alerts) [a.scope, a.seq, a.kind],
  ];

  test('first sight raises nothing and anchors the newest event', () {
    events(3);
    expect(
      anchors.check(chain('instance'), completeScope: 'instance'),
      isEmpty,
    );
    expect(anchors.anchorOf('instance')?.seq, 3);
  });

  test('same seq with another hash is a rewrite and keeps the anchor', () {
    events(3);
    anchors.check(chain('instance'));
    final seen = anchors.anchorOf('instance')!.hash;
    h.rewriteAudit('instance', 3, 'item.created');
    expect(shape(anchors.check(chain('instance'))), [
      ['instance', 3, AnchorAlertKind.rewritten],
    ]);
    events(1);
    expect(
      anchors.check(chain('instance')),
      hasLength(1),
      reason: 'the evidence stays',
    );
    expect(anchors.anchorOf('instance')!.hash, seen);
  });

  test('an anchored seq gone without a covering checkpoint is reported on a complete read', () {
    events(5);
    anchors.check(chain('instance'));
    final served = chain('instance')
        .take(3)
        .toList(); // server rolled back behind what this device saw
    expect(
      anchors.check(served),
      isEmpty,
      reason: 'a partial view proves nothing',
    );
    expect(shape(anchors.check(served, completeScope: 'instance')), [
      ['instance', 5, AnchorAlertKind.vanished],
    ]);
    expect(
      anchors.anchorOf('instance')!.seq,
      5,
      reason: 'anchors never move back',
    );
  });

  test('a checkpoint at or past the anchor covers the purge; one naming the anchor with another hash is a rewrite', () {
    events(5);
    anchors.check(chain('instance'));
    h.purgeAudit('instance', 5);
    expect(
      anchors.check(chain('instance'), completeScope: 'instance'),
      isEmpty,
    );
    expect(anchors.anchorOf('instance')!.seq, 6);
    events(2, 'user:u');
    anchors.check(chain('user:u'));
    h.auditLog.removeWhere((e) => e.scope == 'user:u');
    h.appendAudit(
      'user:u',
      'audit.checkpoint',
      targets: ['seq:2', 'hash:${'f' * 64}'],
    );
    expect(shape(anchors.check(chain('user:u'), completeScope: 'user:u')), [
      ['user:u', 2, AnchorAlertKind.rewritten],
    ]);
  });

  test('anchors live in kv.anchors; an accepted restore empties them', () {
    events(2);
    anchors.check(chain('instance'));
    expect(AuditAnchors(mirror).anchorOf('instance')!.seq, 2);
    mirror.resetForRestore();
    expect(anchors.anchorOf('instance'), isNull);
  });
}
