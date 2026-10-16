// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

const fA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const fB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const idK = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const jump = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

HostMeta host([Map<String, Object?> over = const {}]) => HostMeta.fromJson({
  'schemaVersion': 1,
  'name': 'h',
  'address': 'a',
  'user': null,
  'identityId': null,
  'tags': <String>[],
  'notes': null,
  'startupCommand': null,
  ...over,
});
FolderMeta folder(Map<String, Object?> defaults) => FolderMeta.fromJson({
  'schemaVersion': 1,
  'name': 'f',
  'defaults': {'port': null, 'user': null, 'identityId': null, ...defaults},
});

void main() {
  final folders = {
    fA: folder({'user': 'deploy'}),
    fB: folder({'port': 2200, 'identityId': idK, 'jumpHostId': jump}),
  };
  final parents = <String, String?>{fA: fB, fB: null};
  ResolvedHost resolve(
    HostMeta h,
    String? folderId, {
    Map<String, String?>? parentMap,
  }) => resolveHost(
    h,
    folderId,
    (id) => folders[id],
    parentOf: (id) => (parentMap ?? parents)[id],
  );

  test('nearest folder default wins, with its source', () {
    final r = resolve(host(), fA);
    expect(
      (r.port, r.user, r.identityId, r.jumpHostId),
      (2200, 'deploy', idK, jump),
    );
    expect(r.sources, {
      'port': fB,
      'user': fA,
      'identityId': fB,
      'jumpHostId': fB,
    });
  });

  test('host values win; nothing set gives port 22 and nulls', () {
    final r = resolve(host({'port': 22, 'user': 'root'}), fA);
    expect(
      (r.port, r.user, r.sources['port'], r.sources['user']),
      (22, 'root', 'host', 'host'),
    );
    final d = resolve(host(), null);
    expect(
      (d.port, d.user, d.identityId, d.jumpHostId),
      (22, null, null, null),
    );
    expect(d.sources.values.toSet(), {'default'});
  });

  test('a cycle or a missing folder stops the walk', () {
    final cyc = resolve(host(), fA, parentMap: {fA: fB, fB: fA});
    expect(cyc.port, 2200);
    final missing = resolve(host(), 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
    expect((missing.port, missing.sources['port']), (22, 'default'));
    final cut = resolve(
      host(),
      fA,
      parentMap: {fA: 'ffffffff-ffff-4fff-8fff-ffffffffffff'},
    );
    expect((cut.port, cut.user), (22, 'deploy'));
  });

  test('perMember never inherits the identity', () {
    final r = resolve(host({'identityMode': 'perMember'}), fA);
    expect((r.identityId, r.sources['identityId']), (null, 'default'));
  });

  test('a jumpHostId equal to the host id is ignored, own or inherited', () {
    final own = resolveHost(
      host({'jumpHostId': jump}),
      null,
      (_) => null,
      hostId: jump,
      parentOf: (_) => null,
    );
    expect((own.jumpHostId, own.sources['jumpHostId']), (null, 'default'));
    final inherited = resolveHost(
      host(),
      fA,
      (id) => folders[id],
      hostId: jump,
      parentOf: (id) => parents[id],
    );
    expect(
      (inherited.jumpHostId, inherited.sources['jumpHostId'], inherited.port),
      (null, 'default', 2200),
    );
  });
}
