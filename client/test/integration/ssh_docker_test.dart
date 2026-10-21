// SPDX-License-Identifier: Apache-2.0
@Tags(['docker'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/keys/key_tools.dart';
import 'package:unfeudal_client/src/ssh/ssh_connector.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import 'sshd_image.dart';

const port = 2222;
const password = 'pw-123456';
final hostId = newId();

ConnectTarget target({IdentitySecret? identity}) => ConnectTarget(
  hostId: hostId,
  hostName: 'docker',
  address: '127.0.0.1',
  port: port,
  user: 'camille',
  identity: identity,
);

/// A shell with an 80x24 PTY over a direct connection.
Future<SshShell> connect(ConnectTarget target, SshCallbacks callbacks) async =>
    (await SshConnector().connectHop(target, callbacks)).shell();

Future<String> runCommand(SshShell shell, String command) async {
  final out = StringBuffer();
  final seen = Completer<void>();
  final sub = shell.stdout.listen((chunk) {
    out.write(utf8.decode(chunk, allowMalformed: true));
    if (out.toString().contains('ok\r\n') && !seen.isCompleted) seen.complete();
  });
  shell.write(utf8.encode('$command\n'));
  await seen.future.timeout(const Duration(seconds: 15));
  await sub.cancel();
  return out.toString();
}

/// docker-proxy accepts at once: wait for the sshd banner itself.
Future<void> waitForSsh() async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: const Duration(seconds: 2),
      );
      // Empty when docker-proxy accepted and closed before sshd was up.
      final chunks = await socket
          .take(1)
          .toList()
          .timeout(const Duration(seconds: 2));
      socket.destroy();
      final banner = chunks.isEmpty
          ? ''
          : utf8.decode(chunks.single, allowMalformed: true);
      if (banner.startsWith('SSH-')) return;
    } on Exception {
      // not listening yet
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  fail('sshd did not start');
}

void main() {
  late String container;
  late Directory sshdConf;
  late GeneratedKey key;
  late KnownHostMeta serverPin;

  setUpAll(() async {
    key = await generateEd25519(comment: 'docker-test');
    sshdConf = await Directory.systemTemp.createTemp('sshd');
    File('${sshdConf.path}/kbd.conf')
        .writeAsStringSync('UsePAM yes\nKbdInteractiveAuthentication yes\n');
    final run = await Process.run('docker', [
      'run', '-d', '--rm', '-p', '$port:2222', //
      '-e', 'PUID=1000', '-e', 'PGID=1000',
      '-e',
      'PASSWORD_ACCESS=true',
      '-e',
      'USER_NAME=camille',
      '-e',
      'USER_PASSWORD=$password',
      '-e', 'PUBLIC_KEY=${key.publicKey}',
      '-v', '${sshdConf.path}:/config/sshd/sshd_config.d:ro',
      sshdImage,
    ]);
    if (run.exitCode != 0) fail('docker run: ${run.stderr}');
    container = (run.stdout as String).trim();
    await waitForSsh();
    final first = FakeSshCallbacks(answer: true, password: password);
    await (await connect(target(), first)).close();
    serverPin = first.pins.values.single;
  });

  tearDownAll(() async {
    await Process.run('docker', ['rm', '-f', container]);
    await sshdConf.delete(recursive: true);
  });

  test(
    'a declined unknown key throws HostKeyRejected(unknown), nothing pinned',
    () async {
      final r = FakeSshCallbacks(password: password);
      await expectLater(
        connect(target(), r),
        throwsA(
          isA<HostKeyRejected>().having(
            (e) => e.decision,
            'decision',
            HostKeyDecision.unknown,
          ),
        ),
      );
      expect(r.pins, isEmpty);
    },
  );

  test('an accepted key is pinned; password auth; shell echoes ok', () async {
    final r = FakeSshCallbacks(answer: true, password: password);
    final shell = await connect(target(), r);
    expect(r.pins.values.single.sha256Fingerprint, serverPin.sha256Fingerprint);
    expect(await runCommand(shell, 'echo ok'), contains('ok\r\n'));
    await shell.close();
  });

  test('a tampered pin throws HostKeyRejected(changed)', () async {
    final tampered = KnownHostMeta(
      hostItemId: hostId,
      keyType: serverPin.keyType,
      sha256Fingerprint: 'SHA256:${'B' * 43}',
    );
    await expectLater(
      connect(
        target(),
        FakeSshCallbacks(password: password)..pins[hostId] = tampered,
      ),
      throwsA(
        isA<HostKeyRejected>().having(
          (e) => e.decision,
          'decision',
          HostKeyDecision.changed,
        ),
      ),
    );
  });

  test('a wrong password throws SshAuthFailed', () async {
    await expectLater(
      connect(
        target(),
        FakeSshCallbacks(password: 'wrong-password')..pins[hostId] = serverPin,
      ),
      throwsA(isA<SshAuthFailed>()),
    );
  });

  test('key auth with the generated Ed25519 identity', () async {
    final identity = IdentitySecret(
      kind: IdentityKind.privateKey,
      privateKeyPem: key.privateKeyPem,
    );
    final shell = await connect(
      target(identity: identity),
      FakeSshCallbacks()..pins[hostId] = serverPin,
    );
    expect(await runCommand(shell, 'echo ok'), contains('ok\r\n'));
    await shell.close();
  });

  test('keyboard-interactive answers reach the server', () async {
    final r = FakeSshCallbacks(promptAnswer: password)
      ..pins[hostId] = serverPin;
    final shell = await connect(target(), r);
    expect(r.prompts, isNotEmpty);
    expect(await runCommand(shell, 'echo ok'), contains('ok\r\n'));
    await shell.close();
  });
}
