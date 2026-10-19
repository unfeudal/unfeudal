// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

AuditEvent link(
  String prev,
  int seq, {
  String action = 'device.added',
  List<String>? targets,
  String? ipAddress,
}) {
  final fields = <String, Object?>{
    'scope': 'instance',
    'seq': seq,
    'ts': iso(DateTime.utc(2026, 10, 15).add(Duration(minutes: seq))),
    'actorUser': null,
    'actorDevice': null,
    'ip': null,
    'action': action,
    'targetIds': targets ?? ['t$seq'],
  };
  return AuditEvent.fromJson({
    ...fields,
    'prevHash': prev,
    'hash': auditHash(prev, fields),
    'ipAddress': ?ipAddress,
  });
}

List<AuditEvent> chain(int n) {
  final out = <AuditEvent>[];
  for (var seq = 1; seq <= n; seq++) {
    out.add(link(out.isEmpty ? genesisHash : out.last.hash, seq));
  }
  return out;
}

AuditEvent tampered(AuditEvent e, String action) => AuditEvent.fromJson({
  ...e.toJson(),
  'action': action,
}); // same hash, other content

void main() {
  test('genesis and the reference vector', () {
    expect(genesisHash, '0' * 64);
    expect(
      auditHash(genesisHash, {}),
      '5508d2b710e64bc470079e1b211d9c58e21011e59d0559e422345dc19d659a75',
    );
  });

  test('canonicalJson sorts keys at every level, no spaces, nulls kept', () {
    expect(
      canonicalJson({
        'b': 1,
        'a': {
          'd': null,
          'c': [
            1,
            'x',
            {'z': true, 'y': false},
          ],
        },
      }),
      '{"a":{"c":[1,"x",{"y":false,"z":true}],"d":null},"b":1}',
    );
  });

  test(
    'a whole chain verifies, in any order; raw ipAddress is outside the hash',
    () {
      final c = chain(5);
      expect(verifyChain(c), isNull);
      expect(verifyChain(c.reversed.toList()), isNull);
      expect(
        verifyChain([
          ...chain(2),
          link(chain(2).last.hash, 3, ipAddress: '203.0.113.7'),
        ]),
        isNull,
      );
      expect(verifyChain(const []), isNull);
    },
  );

  test('an edited field, a deleted middle event or a swapped order breaks the chain at that seq', () {
    final c = chain(5);
    expect(
      verifyChain([...c.take(2), tampered(c[2], 'item.purged'), ...c.skip(3)]),
      3,
    );
    expect(verifyChain([...c.take(2), ...c.skip(3)]), 4);
    final swapped = AuditEvent.fromJson({...c[3].toJson(), 'seq': 3});
    expect(verifyChain([...c.take(2), swapped]), 3);
    final otherScope = AuditEvent.fromJson({
      ...c[1].toJson(),
      'scope': 'user:x',
    });
    expect(verifyChain([c[0], otherScope]), 2);
  });

  test('after a purge the chain starts at a checkpoint naming the last purged event', () {
    final c = chain(5);
    final checkpoint = link(
      c[4].hash,
      6,
      action: 'audit.checkpoint',
      targets: ['seq:3', 'hash:${c[2].hash}'],
    );
    expect(verifyChain([c[3], c[4], checkpoint]), isNull);
    expect(verifyChain([c[3], c[4]]), 4, reason: 'no checkpoint');
    final forged = link(
      c[4].hash,
      6,
      action: 'audit.checkpoint',
      targets: ['seq:3', 'hash:${'f' * 64}'],
    );
    expect(
      verifyChain([c[3], c[4], forged]),
      4,
      reason: 'checkpoint names another hash',
    );
    expect(
      verifyChain([c[1], c[2]]),
      2,
      reason: 'a chain not starting at 1 needs a checkpoint',
    );
  });
}
