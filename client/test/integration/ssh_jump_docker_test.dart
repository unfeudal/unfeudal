// SPDX-License-Identifier: Apache-2.0
@Tags(['docker'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/keys/key_tools.dart';
import 'package:unfeudal_client/src/ssh/jump_connector.dart';
import 'package:unfeudal_client/src/ssh/port_forwarder.dart';
import 'package:unfeudal_client/src/ssh/ssh_connector.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';

const net = 'uf-jump',
    bastionName = 'uf-jump-bastion',
    targetName = 'uf-jump-target';
const tunnelMod = 'DOCKER_MODS=linuxserver/mods:openssh-server-ssh-tunnel'; // AllowTcpForwarding yes
const image =
    'lscr.io/linuxserver/openssh-server:10.3_p1-r1-ls239@sha256:bef23ec7e4b6849f8c61b7e5fc1c67fc38bafe100539d5c34fc2d682c582bbf2';

Future<void> docker(List<String> args) async {
  final r = await Process.run('docker', args);
  if (r.exitCode != 0) throw StateError('docker ${args.first}: ${r.stderr}');
}

class Pins implements SshCallbacks {
  final pins = <String, (String, String)>{};
  bool trustNew = true;
  @override
  KnownHostMeta? pinnedKey(String hostId) {
    final p = pins[hostId];
    return p == null
        ? null
        : KnownHostMeta.fromJson({
            'schemaVersion': 1,
            'hostItemId': hostId,
            'keyType': p.$1,
            'sha256Fingerprint': p.$2,
          });
  }

  @override
  Future<bool> confirmHostKey(HostKeyCheck c) async =>
      trustNew && c.decision == HostKeyDecision.unknown;
  @override
  Future<void> pinHostKey(
    String hostId,
    String keyType,
    String fingerprint,
  ) async => pins[hostId] = (keyType, fingerprint);
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
  late GeneratedKey key;
  final bastion = newId(), target = newId();

  ConnectTarget hop(String id, String address, int port) => ConnectTarget(
    hostId: id,
    hostName: address,
    address: address,
    port: port,
    user: 'uf',
    identity: IdentitySecret(
      kind: IdentityKind.privateKey,
      privateKeyPem: key.privateKeyPem,
    ),
  );
  Future<JumpConnection> chain(Pins pins) => JumpConnector(
    sshHopOpener(SshConnector(), pins),
  ).connect([hop(bastion, '127.0.0.1', 22220)], hop(target, targetName, 2222));

  setUpAll(() async {
    key = await generateEd25519();
    await Process.run('docker', ['rm', '-f', bastionName, targetName]);
    await Process.run('docker', ['network', 'create', net]);
    for (final (name, publish) in [
      (bastionName, ['-p', '127.0.0.1:22220:2222']),
      (targetName, <String>[]),
    ]) {
      await docker([
        'run',
        '-d',
        '--name',
        name,
        '--hostname',
        name,
        '--network',
        net,
        ...publish,
        '-e',
        'USER_NAME=uf',
        '-e',
        'PUBLIC_KEY=${key.publicKey}',
        '-e',
        tunnelMod,
        image,
      ]);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (true) {
      try {
        final s = await Socket.connect(InternetAddress.loopbackIPv4, 22220);
        final banner = await s
            .map(utf8.decode)
            .first
            .timeout(const Duration(seconds: 2));
        s.destroy();
        if (banner.startsWith('SSH-')) break;
      } on Object {
        if (DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  });

  tearDownAll(() async {
    await Process.run('docker', ['rm', '-f', bastionName, targetName]);
    await Process.run('docker', ['network', 'rm', net]);
  });

  test(
    'shell on the target through the bastion; each hop pinned separately',
    () async {
      final pins = Pins();
      final conn = await chain(pins);
      final shell = await conn.target.shell();
      shell.write(utf8.encode('hostname\n'));
      await shell.stdout
          .map(utf8.decode)
          .firstWhere((o) => o.contains(targetName))
          .timeout(const Duration(seconds: 10));
      expect(pins.pins.keys, unorderedEquals([bastion, target]));
      await conn.close();
    },
  );

  test(
    'a local forward reaches the target through the chain, on loopback only',
    () async {
      final conn = await chain(Pins());
      final port = await freePort();
      final forwarder = PortForwarder(conn.target.forwardLocal);
      final handle = await forwarder.start(
        PortForward(localPort: port, remoteHost: 'localhost', remotePort: 2222),
      );
      expect(handle.address, InternetAddress.loopbackIPv4);
      final s = await Socket.connect(InternetAddress.loopbackIPv4, port);
      expect(
        await s.map(utf8.decode).first.timeout(const Duration(seconds: 10)),
        startsWith('SSH-2.0-'),
      );
      s.destroy();
      await forwarder.stopAll();
      await conn.close();
    },
  );

  test('a tampered bastion pin stops the chain before the target', () async {
    final pins = Pins()..trustNew = false;
    pins.pins[bastion] = ('ssh-ed25519', 'SHA256:${'A' * 43}');
    await expectLater(
      chain(pins),
      throwsA(
        isA<JumpChainFailed>()
            .having((e) => e.hopIndex, 'hopIndex', 0)
            .having((e) => e.cause, 'cause', isA<HostKeyRejected>()),
      ),
    );
    expect(pins.pins.containsKey(target), isFalse);
  });
}
