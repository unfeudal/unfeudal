// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/orgs/key_handoff.dart';
import 'package:unfeudal_client/src/orgs/member_pins.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/org_fixtures.dart';

void main() {
  late ClientOrg c;
  late KeyHandoff handoff;
  late ({SimpleKeyPair pair, Uint8List publicKey}) mia;
  final miaId = newId(), f = newId(), g = newId();
  late FolderKeys keys;
  setUp(() async {
    c = await ClientOrg.start();
    handoff = KeyHandoff(api: c.api, keyring: c.keyring, pins: c.pins);
    mia = await memberKeys();
    keys = FolderKeys.generate(1);
    await c.keyring.put(f, keys);
    await c.keyring.put(g, FolderKeys.generate(1));
  });

  OrgBlock block({
    String role = 'admin',
    bool secret = true,
    int version = 1,
    List<int>? key,
    bool? disabled,
  }) => orgBlock(
    role: role,
    members: [
      c.me(),
      memberRow(
        miaId,
        status: 'confirmed',
        publicKey: key ?? mia.publicKey,
        disabled: disabled,
      ),
    ],
    folderTree: [node(f), node(g)],
    keyRequests: [
      {
        'orgId': testOrgId,
        'folderId': f,
        'userId': miaId,
        'version': version,
        'secret': secret,
      },
    ],
  );
  List<Map<String, Object?>> uploads() => [
    for (final x in c.h.orgCalls)
      if (x.route == 'PUT /folders/$f/keys') x.body,
  ];

  test('an unpinned member gets nothing and is listed to confirm; once confirmed, the wrap opens to the folder keys', () async {
    final first = await handoff.run(block());
    expect(first.sent, isEmpty);
    expect(first.unconfirmed, {miaId});
    expect(uploads(), isEmpty);
    expect(c.pins.pinOf(miaId), isNull);
    await c.pins.pin(
      miaId,
      mia.publicKey,
      verified: false,
    ); // confirmed without comparing codes
    expect((await handoff.run(block())).sent, {(f, miaId)});
    final body = uploads().single;
    expect((body['version'], body['history']), (1, null));
    final wrap = WrappedFolderKeys.fromJson((body['wrapped']! as List).single);
    final opened = await wrap.unwrap(f, mia.pair);
    expect(
      (wrap.userId, b64(opened.metaKey), b64(opened.secretKey!)),
      (miaId, b64(keys.metaKey), b64(keys.secretKey!)),
    );
  });

  test('a disabled member never gets a wrap', () async {
    final report = await handoff.run(block(disabled: true));
    expect(report.sent, isEmpty);
    expect(uploads(), isEmpty);
    expect(c.pins.pinOf(miaId), isNull);
  });

  test('no secret wrap when the request does not need it', () async {
    await c.pins.pin(miaId, mia.publicKey, verified: true);
    await handoff.run(block(secret: false));
    expect(
      (uploads().single['wrapped']! as List).single,
      containsPair('secret', null),
    );
  });

  test(
    'a key different from the pin is never sealed to and raises an alert',
    () async {
      await c.pins.pin(miaId, mia.publicKey, verified: true);
      final swapped = (await memberKeys()).publicKey;
      final report = await handoff.run(block(key: swapped));
      expect(report.sent, isEmpty);
      expect(report.alerts, {miaId});
      expect(uploads(), isEmpty);
      expect(c.pins.check(miaId, swapped), PinCheck.changed);
    },
  );

  test('skips requests for a version this device does not hold, non-admin blocks, and groups wraps per folder', () async {
    expect((await handoff.run(block(version: 2))).sent, isEmpty);
    expect((await handoff.run(block(role: 'member'))).sent, isEmpty);
    final other = newId(), otherKeys = await memberKeys();
    await c.pins.pin(miaId, mia.publicKey, verified: true);
    await c.pins.pin(other, otherKeys.publicKey, verified: false);
    final two = orgBlock(
      role: 'admin',
      members: [
        c.me(),
        memberRow(miaId, status: 'confirmed', publicKey: mia.publicKey),
        memberRow(other, status: 'confirmed', publicKey: otherKeys.publicKey),
      ],
      folderTree: [node(f)],
      keyRequests: [
        {
          'orgId': testOrgId,
          'folderId': f,
          'userId': miaId,
          'version': 1,
          'secret': true,
        },
        {
          'orgId': testOrgId,
          'folderId': f,
          'userId': other,
          'version': 1,
          'secret': false,
        },
      ],
    );
    expect((await handoff.run(two)).sent, {(f, miaId), (f, other)});
    expect((uploads().single['wrapped']! as List), hasLength(2));
  });
}
