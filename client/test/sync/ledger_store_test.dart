// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/sync/ledger_store.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  final key = SymmetricCipher.newKey();
  final h = newId();
  KnownHostMeta pin(String fp) => KnownHostMeta.fromJson({
    'schemaVersion': 1,
    'hostItemId': h,
    'keyType': 'ssh-ed25519',
    'sha256Fingerprint': 'SHA256:${fp * 43}',
  });

  test(
    'empty ledger: no marks, nothing is a replay, seq starts at 1',
    () async {
      final l = LedgerStore(LocalMirror.inMemory());
      expect(await l.load(key), isTrue);
      expect(l.mark(h, PayloadPart.meta), 0);
      expect(l.isReplay(h, PayloadPart.meta, null), isFalse);
      expect(l.nextSeq(h), 1);
    },
  );

  test(
    'marks rise only, per part; nextSeq covers marks and this session',
    () async {
      final l = LedgerStore(LocalMirror.inMemory());
      await l.load(key);
      l
        ..confirm(h, PayloadPart.meta, 5)
        ..confirm(h, PayloadPart.meta, 3)
        ..confirm(h, PayloadPart.secret, 2);
      expect(
        (l.mark(h, PayloadPart.meta), l.mark(h, PayloadPart.secret)),
        (5, 2),
      );
      expect(l.nextSeq(h), 6);
      expect(l.nextSeq(h), 7); // sealed this session, not yet confirmed
      expect(l.mark(h, PayloadPart.meta), 5);
    },
  );

  test('replay: lower seq, or no seq once a mark exists', () async {
    final l = LedgerStore(LocalMirror.inMemory());
    await l.load(key);
    l.confirm(h, PayloadPart.meta, 4);
    expect(l.isReplay(h, PayloadPart.meta, 3), isTrue);
    expect(l.isReplay(h, PayloadPart.meta, null), isTrue);
    expect(l.isReplay(h, PayloadPart.meta, 4), isFalse);
    expect(l.isReplay(h, PayloadPart.secret, 1), isFalse);
  });

  test('save seals under keyId user; load restores marks and pins', () async {
    final m = LocalMirror.inMemory();
    final l = LedgerStore(m);
    await l.load(key);
    l.confirm(h, PayloadPart.meta, 4);
    await l.setHostPin(h, pin('A'));
    await l.save();
    final env = Envelope.fromJson(jsonDecode(m.getKv(KvKey.ledger)!));
    expect(env.keyId, 'user');
    expect(m.getKv(KvKey.ledger), isNot(contains('SHA256')));
    final again = LedgerStore(m);
    expect(await again.load(key), isTrue);
    expect(
      (again.mark(h, PayloadPart.meta), again.hostPin(h)!.sha256Fingerprint),
      (4, 'SHA256:${'A' * 43}'),
    );
  });

  test(
    'a ledger that fails to open is reported, then restarts empty',
    () async {
      final m = LocalMirror.inMemory();
      final l = LedgerStore(m);
      await l.load(key);
      await l.setHostPin(h, pin('A'));
      final other = LedgerStore(m);
      expect(await other.load(SymmetricCipher.newKey()), isFalse);
      expect(other.hostPin(h), isNull);
      m.setKv(KvKey.ledger, '{"v":1}');
      expect(await LedgerStore(m).load(key), isFalse);
    },
  );

  test('member pins and startup approvals; reset empties marks and keeps pins and approvals', () async {
    final m = LocalMirror.inMemory();
    final l = LedgerStore(m);
    await l.load(key);
    final u = newId();
    final approved =
        '${'h' * 43}='; // SHA-256 in base64, as the ledger requires
    await l.setMemberPin(u, (fingerprint: 'a' * 40, verified: true));
    await l.setHostPin(h, pin('A'));
    await l.approveStartup(h, approved);
    expect(
      (l.startupApproval(h), l.startupApproval(newId())),
      (approved, null),
    );
    l.confirm(h, PayloadPart.meta, 4);
    expect(l.memberPin(u)!.verified, isTrue);
    await l.reset();
    expect(
      (
        l.memberPin(u)!.verified,
        l.hostPin(h)!.sha256Fingerprint,
        l.mark(h, PayloadPart.meta),
        l.nextSeq(h),
      ),
      (true, 'SHA256:${'A' * 43}', 0, 1),
    );
    final again = LedgerStore(m);
    await again.load(key);
    expect(
      (
        again.memberPin(u)!.verified,
        again.hostPin(h)!.sha256Fingerprint,
        again.mark(h, PayloadPart.meta),
      ),
      (true, 'SHA256:${'A' * 43}', 0),
    );
    expect(again.startupApproval(h), approved);
  });
}
