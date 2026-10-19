// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/ssh/ssh_connector.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

final host = newId();
KnownHostMeta pin(String type, String c) => KnownHostMeta.fromJson({
  'schemaVersion': 1,
  'hostItemId': host,
  'keyType': type,
  'sha256Fingerprint': 'SHA256:${c * 43}',
});

class Recorder implements SshCallbacks {
  Recorder({this.pinned, this.answer = false});
  KnownHostMeta? pinned;
  bool answer;
  final asked = <HostKeyCheck>[];
  final pins = <String>[];
  @override
  KnownHostMeta? pinnedKey(String hostId) => pinned;
  @override
  Future<bool> confirmHostKey(HostKeyCheck c) async {
    asked.add(c);
    return answer;
  }

  @override
  Future<void> pinHostKey(
    String hostId,
    String keyType,
    String fingerprint,
  ) async => pins.add('$keyType $fingerprint');
  @override
  Future<String?> askPassword(String target) async => null;
  @override
  Future<List<String>?> answerPrompts(
    String name,
    String instruction,
    List<SshPrompt> prompts,
  ) async => null;
}

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
  Recorder r, {
  String type = 'ssh-ed25519',
  String c = 'A',
}) => SshConnector.verifyHostKey(
  hostId: host,
  hostName: 'web',
  keyType: type,
  fingerprint: 'SHA256:${c * 43}',
  callbacks: r,
);

void main() {
  test('decideHostKey', () {
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
    final no = Recorder();
    expect(await verify(no), isFalse);
    expect(no.asked.single.decision, HostKeyDecision.unknown);
    expect(no.pins, isEmpty);
    final yes = Recorder(answer: true);
    expect(await verify(yes), isTrue);
    expect(yes.pins, ['ssh-ed25519 SHA256:${'A' * 43}']);
  });

  test(
    'changed key: refused when declined, pin untouched; re-pinned only on yes',
    () async {
      final r = Recorder(pinned: pin('ssh-ed25519', 'A'));
      expect(await verify(r, c: 'B'), isFalse);
      expect(r.asked.single.decision, HostKeyDecision.changed);
      expect(r.asked.single.pinned!.sha256Fingerprint, 'SHA256:${'A' * 43}');
      expect(r.pins, isEmpty);
      r.answer = true;
      expect(await verify(r, c: 'B'), isTrue);
      expect(r.pins.single, endsWith('B' * 43));
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
        connector.connect(target, Recorder()),
        throwsA(isA<SshConnectionFailed>()),
      );
    },
  );

  test('trusted key never asks', () async {
    final r = Recorder(pinned: pin('ssh-ed25519', 'A'));
    expect(await verify(r), isTrue);
    expect(r.asked, isEmpty);
  });
}
