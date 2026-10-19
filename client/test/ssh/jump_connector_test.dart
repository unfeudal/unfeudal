// SPDX-License-Identifier: Apache-2.0
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/ssh/jump_connector.dart';
import 'package:unfeudal_client/src/ssh/ssh_connector.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';

ConnectTarget t(String id) => ConnectTarget(
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

class _Refuse implements SshCallbacks {
  final asked = <String>[];
  @override
  KnownHostMeta? pinnedKey(String hostId) => null;
  @override
  Future<bool> confirmHostKey(HostKeyCheck c) async {
    asked.add(c.hostId);
    return false;
  }

  @override
  Future<void> pinHostKey(
    String hostId,
    String keyType,
    String fingerprint,
  ) async {}
  @override
  Future<String?> askPassword(String target) async => null;
  @override
  Future<List<String>?> answerPrompts(
    String name,
    String instruction,
    List<SshPrompt> prompts,
  ) async => null;
}

void main() {
  test('hops open outermost first, each over the previous forward; close runs innermost first', () async {
    final log = <String>[];
    final c = JumpConnector((target, {over}) async {
      log.add('open ${target.hostId} over ${(over as FakeChannel?)?.label}');
      return _Hop(target.hostId, log);
    });
    final conn = await c.connect([t('j2'), t('j1')], t('web'));
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
      final c = JumpConnector((target, {over}) async {
        if (target.hostId == 'j1') {
          throw const HostKeyRejected(HostKeyDecision.changed, hostId: 'j1');
        }
        log.add('open ${target.hostId}');
        return _Hop(target.hostId, log);
      });
      await expectLater(
        c.connect([t('j2'), t('j1')], t('web')),
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
    final conn = await JumpConnector((target, {over}) async {
      expect(over, isNull);
      return _Hop(target.hostId, []);
    }).connect(const [], t('web'));
    expect(conn.hops, isEmpty);
  });

  test('sshHopOpener checks each hop with its own id; a refused bastion key stops before the target', () async {
    final ssh = FakeSshConnector()
      ..keyType = 'ssh-ed25519'
      ..fingerprint = 'SHA256:${'A' * 43}';
    final cb = _Refuse();
    await expectLater(
      JumpConnector(sshHopOpener(ssh, cb)).connect([t('bastion')], t('web')),
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
    expect(cb.asked, ['bastion']);
    expect(ssh.targets.map((x) => x.hostId), ['bastion']);
  });
}
