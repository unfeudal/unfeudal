// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/orgs/folder_keyring.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/org_fixtures.dart';

void main() {
  final userKey = Uint8List.fromList(List.filled(32, 4));
  final f = newId();
  late LocalMirror m;
  late FolderKeyring ring;
  late ({SimpleKeyPair pair, Uint8List publicKey}) me;
  setUp(() async {
    m = LocalMirror.inMemory();
    ring = FolderKeyring(m);
    expect(await ring.load(userKey), isTrue);
    me = await memberKeys();
  });

  Future<Set<String>> serve(
    List<Map<String, Object?>> wraps, {
    List<Map<String, Object?>> history = const [],
  }) => ring.apply(orgBlock(wrappedKeys: wraps, keyHistory: history), me.pair);
  bool same(FolderKeys? a, FolderKeys b) =>
      a != null &&
      a.version == b.version &&
      b64(a.metaKey) == b64(b.metaKey) &&
      (a.secretKey == null
          ? b.secretKey == null
          : b.secretKey != null && b64(a.secretKey!) == b64(b.secretKey!));

  test('first sight: unwrapped and kept, sealed in kv.keyring, reloaded after a restart', () async {
    final v1 = FolderKeys.generate(1);
    expect(await serve([await wrappedRow(v1, f, me.publicKey)]), isEmpty);
    expect(same(ring.current(f), v1), isTrue);
    expect(m.getKv(KvKey.keyring), isNot(contains(b64(v1.metaKey))));
    final again = FolderKeyring(m);
    await again.load(userKey);
    expect(same(again.keyFor(f, 1), v1), isTrue);
  });

  test('a rotation that continues the held key is accepted; old versions stay readable', () async {
    final v1 = FolderKeys.generate(1), v2 = FolderKeys.generate(2);
    await serve([await wrappedRow(v1, f, me.publicKey)]);
    expect(
      await serve(
        [await wrappedRow(v2, f, me.publicKey)],
        history: [
          await historyRow(v2, [v1], f),
        ],
      ),
      isEmpty,
    );
    expect((ring.current(f)!.version, same(ring.keyFor(f, 1), v1)), (2, true));
  });

  test('a served key that does not continue the held one is refused and the held one kept', () async {
    final v1 = FolderKeys.generate(1);
    await serve([await wrappedRow(v1, f, me.publicKey)]);
    final swapped = FolderKeys.generate(1);
    expect(await serve([await wrappedRow(swapped, f, me.publicKey)]), {f});
    final v2 = FolderKeys.generate(2);
    expect(
      await serve(
        [await wrappedRow(v2, f, me.publicKey)],
        history: [
          await historyRow(v2, [FolderKeys.generate(1)], f),
        ],
      ),
      {f},
    );
    expect(await serve([await wrappedRow(v2, f, me.publicKey)]), {
      f,
    }, reason: 'no history to continue through');
    final secretSwap = FolderKeys(
      1,
      v1.metaKey,
      FolderKeys.generate(1).secretKey,
    );
    expect(await serve([await wrappedRow(secretSwap, f, me.publicKey)]), {f});
    expect(same(ring.current(f), v1), isTrue);
  });

  test('a rollback to an older version is refused', () async {
    final v1 = FolderKeys.generate(1), v2 = FolderKeys.generate(2);
    await serve(
      [await wrappedRow(v2, f, me.publicKey)],
      history: [
        await historyRow(v2, [v1], f),
      ],
    );
    expect(await serve([await wrappedRow(v1, f, me.publicKey)]), {f});
    expect(ring.current(f)!.version, 2);
  });

  test('losing connect is not a swap: a meta-only key at the next version is accepted', () async {
    final v1 = FolderKeys.generate(1), v2 = FolderKeys.generate(2);
    await serve([await wrappedRow(v1, f, me.publicKey)]);
    final h = await historyRow(FolderKeys(2, v2.metaKey, null), [
      FolderKeys(1, v1.metaKey, null),
    ], f);
    expect(
      await serve(
        [await wrappedRow(v2, f, me.publicKey, secret: false)],
        history: [h],
      ),
      isEmpty,
    );
    expect(ring.current(f)!.version, 2);
    expect(ring.current(f)!.secretKey, isNull);
  });

  test(
    'a wrap under another folder\'s label or for another key pair is refused',
    () async {
      final row = await wrappedRow(
        FolderKeys.generate(1),
        newId(),
        me.publicKey,
      );
      expect(
        await serve([
          {...row, 'folderId': f},
        ]),
        {f},
      );
      final other = await memberKeys();
      expect(
        await serve([
          await wrappedRow(FolderKeys.generate(1), f, other.publicKey),
        ]),
        {f},
      );
      expect(ring.current(f), isNull);
    },
  );

  test('gaining connect at the same version: the secret part completes the held meta-only key', () async {
    final v1 = FolderKeys.generate(1);
    await serve([await wrappedRow(v1, f, me.publicKey, secret: false)]);
    expect(ring.current(f)!.secretKey, isNull);
    expect(await serve([await wrappedRow(v1, f, me.publicKey)]), isEmpty);
    expect(same(ring.current(f), v1), isTrue);
    final otherMeta = FolderKeys(
      1,
      FolderKeys.generate(1).metaKey,
      v1.secretKey,
    );
    expect(await serve([await wrappedRow(otherMeta, f, me.publicKey)]), {f});
    expect(same(ring.current(f), v1), isTrue);
  });

  test('put keeps keys this device made; a keyring that does not open is reported and restarts empty', () async {
    final mine = FolderKeys.generate(1);
    await ring.put(f, mine);
    expect(same(ring.current(f), mine), isTrue);
    final wrongKey = FolderKeyring(m);
    expect(
      await wrongKey.load(Uint8List.fromList(List.filled(32, 9))),
      isFalse,
    );
    expect(wrongKey.current(f), isNull);
  });
}
