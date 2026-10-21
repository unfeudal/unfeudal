// SPDX-License-Identifier: Apache-2.0
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/ssh/jump_connector.dart';
import 'package:unfeudal_client/src/ssh/ssh_connector.dart';

import '../support/fakes.dart';

ConnectTarget target(String id) => ConnectTarget(
  hostId: id,
  hostName: id,
  address: '$id.lan',
  port: 22,
  user: 'u',
);

class _Hop implements HopClient {
  _Hop(this.id, this.log);
  final String id;
  final List<String> log;
  @override
  Future<SSHSocket> forwardLocal(String host, int port) async {
    log.add('forward $id>$host:$port');
    return FakeChannel('$id>$host');
  }

  @override
  Future<SshShell> shell() async => FakeShell();
  @override
  Future<void> close() async => log.add('close $id');
}

void main() {
  test('hops open outermost first, each over the previous forward; close runs innermost first', () async {
    final log = <String>[];
    final conn = await connectChain(
      (hop, {over}) async {
        log.add('open ${hop.hostId} over ${(over as FakeChannel?)?.label}');
        return _Hop(hop.hostId, log);
      },
      [target('j2'), target('j1')],
      target('web'),
    );
    expect(log, [
      'open j2 over null',
      'forward j2>j1.lan:22',
      'open j1 over j2>j1.lan',
      'forward j1>web.lan:22',
      'open web over j1>web.lan',
    ]);
    await conn.close();
    expect(log.skip(5), ['close web', 'close j1', 'close j2']);
  });

  test(
    'failure at a hop closes the opened hops and never opens the next',
    () async {
      final log = <String>[];
      Future<HopClient> open(ConnectTarget hop, {SSHSocket? over}) async {
        if (hop.hostId == 'j1') {
          throw const HostKeyRejected(HostKeyDecision.changed, hostId: 'j1');
        }
        log.add('open ${hop.hostId}');
        return _Hop(hop.hostId, log);
      }

      await expectLater(
        connectChain(open, [target('j2'), target('j1')], target('web')),
        throwsA(
          isA<JumpChainFailed>()
              .having((e) => e.hostId, 'hostId', 'j1')
              .having((e) => e.hostName, 'hostName', 'j1')
              .having((e) => e.hopIndex, 'hopIndex', 1)
              .having((e) => e.cause, 'cause', isA<HostKeyRejected>()),
        ),
      );
      expect(log, ['open j2', 'forward j2>j1.lan:22', 'close j2']);
    },
  );

  test('no hops: the target is opened directly', () async {
    final conn = await connectChain(
      (hop, {over}) async {
        expect(over, isNull);
        return _Hop(hop.hostId, []);
      },
      const [],
      target('web'),
    );
    expect(conn.hops, isEmpty);
  });

  test('connectHop checks each hop with its own id; a refused bastion key stops before the target', () async {
    final ssh = FakeSshConnector()
      ..keyType = 'ssh-ed25519'
      ..fingerprint = 'SHA256:${'A' * 43}';
    final cb = FakeSshCallbacks();
    await expectLater(
      connectChain((hop, {over}) => ssh.connectHop(hop, cb, over: over), [
        target('bastion'),
      ], target('web')),
      throwsA(
        isA<JumpChainFailed>()
            .having((e) => e.hostId, 'hostId', 'bastion')
            .having(
              (e) => e.cause,
              'cause',
              isA<HostKeyRejected>().having((r) => r.hostId, 'hop', 'bastion'),
            ),
      ),
    );
    expect(cb.asked.map((c) => c.hostId), ['bastion']);
    expect(ssh.targets.map((x) => x.hostId), ['bastion']);
  });
}
