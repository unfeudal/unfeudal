// SPDX-License-Identifier: Apache-2.0

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

  test('trusted key never asks', () async {
    final r = Recorder(pinned: pin('ssh-ed25519', 'A'));
    expect(await verify(r), isTrue);
    expect(r.asked, isEmpty);
  });
}
