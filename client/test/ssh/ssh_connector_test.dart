// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/ssh/ssh_connector.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';

final host = newId();
KnownHostMeta pin(String type, String fingerprintChar) =>
    KnownHostMeta.fromJson({
      'schemaVersion': 1,
      'hostItemId': host,
      'keyType': type,
      'sha256Fingerprint': 'SHA256:${fingerprintChar * 43}',
    });

/// A server that hangs up before saying anything.
class ClosedSocket implements SSHSocket {
  @override
  Stream<Uint8List> get stream => const Stream.empty();
  @override
  StreamSink<List<int>> get sink => StreamController<List<int>>().sink;
  @override
  Future<void> get done async {}
  @override
  Future<void> close() async {}
  @override
  void destroy() {}
  @override
  Future<void> flush() async {}
}

Future<bool> verify(
  FakeSshCallbacks callbacks, {
  String type = 'ssh-ed25519',
  String fingerprintChar = 'A',
}) async => (await SshConnector.verifyHostKey(
  hostId: host,
  hostName: 'web',
  keyType: type,
  fingerprint: 'SHA256:${fingerprintChar * 43}',
  callbacks: callbacks,
)).accepted;

void main() {
  test('no pin is unknown, the same type and fingerprint trusted, anything else changed', () {
    expect(
      decideHostKey(null, 'ssh-ed25519', 'SHA256:${'A' * 43}'),
      HostKeyDecision.unknown,
    );
    expect(
      decideHostKey(
        pin('ssh-ed25519', 'A'),
        'ssh-ed25519',
        'SHA256:${'A' * 43}',
      ),
      HostKeyDecision.trusted,
    );
    expect(
      decideHostKey(
        pin('ssh-ed25519', 'A'),
        'ssh-ed25519',
        'SHA256:${'B' * 43}',
      ),
      HostKeyDecision.changed,
    );
    expect(
      decideHostKey(pin('ssh-ed25519', 'A'), 'ssh-rsa', 'SHA256:${'A' * 43}'),
      HostKeyDecision.changed,
    );
  });

  test('unknown key asks and pins only on yes', () async {
    final no = FakeSshCallbacks();
    expect(await verify(no), isFalse);
    expect(no.asked.single.decision, HostKeyDecision.unknown);
    expect(no.pins, isEmpty);
    final yes = FakeSshCallbacks(answer: true);
    expect(await verify(yes), isTrue);
    expect(
      (yes.pins[host]!.keyType, yes.pins[host]!.sha256Fingerprint),
      ('ssh-ed25519', 'SHA256:${'A' * 43}'),
    );
  });

  test(
    'changed key: refused when declined, pin untouched; re-pinned only on yes',
    () async {
      final callbacks = FakeSshCallbacks()
        ..pins[host] = pin('ssh-ed25519', 'A');
      expect(await verify(callbacks, fingerprintChar: 'B'), isFalse);
      expect(callbacks.asked.single.decision, HostKeyDecision.changed);
      expect(
        callbacks.asked.single.pinned!.sha256Fingerprint,
        'SHA256:${'A' * 43}',
      );
      expect(callbacks.pins[host]!.sha256Fingerprint, 'SHA256:${'A' * 43}');
      callbacks.answer = true;
      expect(await verify(callbacks, fingerprintChar: 'B'), isTrue);
      expect(callbacks.pins[host]!.sha256Fingerprint, endsWith('B' * 43));
    },
  );

  test(
    'a connection closed before authentication throws SshConnectionFailed',
    () async {
      final connector = SshConnector(
        openSocket: (_, _) async => ClosedSocket(),
      );
      final target = ConnectTarget(
        hostId: host,
        hostName: 'web',
        address: 'web',
        port: 22,
        user: 'root',
      );
      await expectLater(
        connector.connectHop(target, FakeSshCallbacks()),
        throwsA(isA<SshConnectionFailed>()),
      );
    },
  );

  test('trusted key never asks', () async {
    final callbacks = FakeSshCallbacks()..pins[host] = pin('ssh-ed25519', 'A');
    expect(await verify(callbacks), isTrue);
    expect(callbacks.asked, isEmpty);
  });
}
