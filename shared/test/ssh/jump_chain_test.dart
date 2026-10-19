// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

ResolvedHost r(String? jump) => ResolvedHost(
  port: 22,
  jumpHostId: jump,
  sources: {'jumpHostId': jump == null ? 'default' : 'host'},
);
ResolvedHost? Function(String) table(Map<String, String?> jumps) =>
    (id) => jumps.containsKey(id) ? r(jumps[id]) : null;

void main() {
  test('no jump host: empty chain', () {
    expect(resolveJumpChain('t', table({'t': null})), isEmpty);
  });

  test('chain is outermost first, target excluded', () {
    expect(resolveJumpChain('t', table({'t': 'j1', 'j1': 'j2', 'j2': null})), [
      'j2',
      'j1',
    ]);
  });

  test('loops are refused', () {
    for (final jumps in [
      {'t': 'a', 'a': 't'},
      {'t': 'a', 'a': 'b', 'b': 'a'},
    ]) {
      expect(
        () => resolveJumpChain('t', table(jumps)),
        throwsA(isA<JumpLoop>()),
        reason: '$jumps',
      );
    }
  });

  test('8 jump hosts pass, 9 are too deep', () {
    Map<String, String?> line(int n) => {
      't': 'h1',
      for (var i = 1; i <= n; i++) 'h$i': i == n ? null : 'h${i + 1}',
    };
    expect(resolveJumpChain('t', table(line(8))), hasLength(8));
    expect(
      () => resolveJumpChain('t', table(line(9))),
      throwsA(isA<JumpTooDeep>()),
    );
  });

  test('a missing jump host is named', () {
    expect(
      () => resolveJumpChain('t', table({'t': 'gone'})),
      throwsA(isA<JumpHostMissing>().having((e) => e.hostId, 'hostId', 'gone')),
    );
  });

  test('a folder default is inherited; a bastion inside that folder connects directly', () {
    const prod = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const bastion = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    const web = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
    final folders = {
      prod: FolderMeta.fromJson({
        'schemaVersion': 1,
        'name': 'prod',
        'defaults': {
          'port': null,
          'user': null,
          'identityId': null,
          'jumpHostId': bastion,
        },
      }),
    };
    HostMeta host(String name) => HostMeta.fromJson({
      'schemaVersion': 1,
      'name': name,
      'address': name,
      'user': null,
      'identityId': null,
      'tags': <String>[],
      'notes': null,
      'startupCommand': null,
    });
    final hosts = <String, (HostMeta, String?)>{
      web: (host('web'), prod),
      bastion: (host('bastion'), null),
    };
    ResolvedHost? lookup(String id) {
      final h = hosts[id];
      return h == null
          ? null
          : resolveHost(
              h.$1,
              h.$2,
              (f) => folders[f],
              hostId: id,
              parentOf: (_) => null,
            );
    }

    expect(resolveJumpChain(web, lookup), [bastion]);
    hosts[bastion] = (host('bastion'), prod);
    expect(resolveJumpChain(web, lookup), [bastion]);
    expect(resolveJumpChain(bastion, lookup), isEmpty);
  });
}
