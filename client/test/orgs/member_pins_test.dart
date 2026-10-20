// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/orgs/block_permissions.dart';
import 'package:unfeudal_client/src/orgs/member_pins.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/org_fixtures.dart';

void main() {
  late ClientOrg c;
  final mia = newId();
  setUp(() async => c = await ClientOrg.start());

  Map<String, Object?> pinMeta(String fingerprint, {bool verified = false}) => {
    'schemaVersion': 1,
    'userId': mia,
    'fingerprint': fingerprint,
    'verified': verified,
  };

  test('a pin without comparison is unverified, in the ledger and as a memberPin item', () async {
    final k = await memberKeys();
    expect(c.pins.check(mia, k.publicKey), PinCheck.unpinned);
    await c.pins.pin(mia, k.publicKey, verified: false);
    expect(c.pins.check(mia, k.publicKey), PinCheck.matches);
    expect(c.pins.pinOf(mia), (
      fingerprint: keyFingerprint(k.publicKey),
      verified: false,
    ));
    final queued = c.mirror.outbox().single.item;
    expect((queued.type, queued.scope), ('memberPin', ItemScope.personal));
    expect(c.pins.check(mia, (await memberKeys()).publicKey), PinCheck.changed);
  });

  test('pinning the same key again as verified marks it verified', () async {
    final k = await memberKeys();
    await c.pins.pin(mia, k.publicKey, verified: false);
    expect(c.pins.pinOf(mia)!.verified, isFalse);
    await c.pins.pin(mia, k.publicKey, verified: true);
    expect(c.pins.pinOf(mia)!.verified, isTrue);
    await c.vault.reload();
    expect(c.vault.ofKind(ItemKind.memberPin).single.meta!['verified'], isTrue);
  });

  test(
    'the ledger pin wins over a deleted or reverted memberPin item',
    () async {
      final k = await memberKeys();
      await c.pins.pin(mia, k.publicKey, verified: true);
      await c.sync.syncNow();
      final pinItem = c.mirror.items().singleWhere(
        (i) => i.type == 'memberPin',
      );
      c.mirror.deleteItems([pinItem.id]);
      await c.vault.reload();
      expect(c.pins.pinOf(mia), (
        fingerprint: keyFingerprint(k.publicKey),
        verified: true,
      ));
      final forged = await c.vault.sealer.seal(
        id: pinItem.id,
        type: 'memberPin',
        revision: 5,
        meta: pinMeta('b' * 40),
      );
      c.mirror.upsertItems([forged]);
      await c.vault.reload();
      expect(c.pins.check(mia, k.publicKey), PinCheck.matches);
    },
  );

  test('a pin made on another device seeds the ledger', () async {
    final k = await memberKeys();
    c.mirror.upsertItems([
      await c.vault.sealer.seal(
        id: newId(),
        type: 'memberPin',
        revision: 1,
        meta: pinMeta(keyFingerprint(k.publicKey), verified: true),
      ),
    ]);
    await c.vault.reload();
    c.pins.seed();
    expect(c.pins.pinOf(mia)!.verified, isTrue);
    expect(
      c.vault.ledger.memberPin(mia)!.fingerprint,
      keyFingerprint(k.publicKey),
    );
  });

  test('explainFromBlock resolves a member from the block rows', () {
    final f = newId(), g = newId(), team = newId();
    final block = orgBlock(
      members: [memberRow(mia)],
      folderTree: [node(f), node(g, f)],
      teams: [
        {
          'orgId': testOrgId,
          'id': team,
          'name': 'Ops',
          'memberIds': [mia],
        },
      ],
      acl: [
        aclRow(f, team, type: 'team', allow: ['connect']),
        aclRow(g, mia, deny: ['connect']),
      ],
    );
    expect(
      explainFromBlock(block, testOrgId, userId: mia, folderId: g).effective,
      {Permission.view},
    );
    expect(
      explainFromBlock(block, testOrgId, userId: mia, folderId: f).effective,
      {Permission.view, Permission.connect},
    );
    expect(
      explainFromBlock(
        block,
        testOrgId,
        userId: mia,
        folderId: newId(),
      ).effective,
      isEmpty,
    );
    final admin = orgBlock(
      role: 'admin',
      members: [memberRow(mia, role: 'admin', status: 'confirmed')],
      folderTree: [node(f)],
    );
    expect(
      explainFromBlock(admin, testOrgId, userId: mia, folderId: f).effective,
      Permission.values.toSet(),
    );
  });
}
