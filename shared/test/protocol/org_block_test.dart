// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

const o = '3c5e7a9b-1d2f-4e6a-8b0c-2d4f6a8c0e1a';
const f = '7e9a1c3e-5f7b-4d9f-b1a3-c5e7a9b1d3f5';
const u = '5d1e9a7c-2b3f-4c8d-9e0a-1b2c3d4e5f60';
const t = '2e4f6a8c-0b1d-4e3f-a5b7-c9d1e3f5a7b9';
final env = {
  'v': 1,
  'alg': 'xchacha20poly1305',
  'keyId': 'sealed:folder:$f:v1:meta',
  'nonce': b64(List.filled(24, 0)),
  'ct': b64(List.filled(48, 0)),
};

final block = <String, Object?>{
  'orgCursor': 12,
  'orgs': [
    {
      'id': o,
      'name': 'Acme',
      'role': 'admin',
      'status': 'confirmed',
      'settings': {'mascot': false},
    },
  ],
  'members': [
    {
      'orgId': o,
      'userId': u,
      'email': 'a@b.c',
      'role': 'member',
      'status': 'confirmed',
      'publicKey': b64(List.filled(32, 9)),
      'disabled': true,
    },
    {'orgId': o, 'userId': t, 'email': 'd@e.f', 'role': 'owner'},
  ],
  'teams': [
    {
      'orgId': o,
      'id': t,
      'name': 'Ops',
      'memberIds': [u],
    },
  ],
  'acl': [
    {
      'orgId': o,
      'folderId': f,
      'principalType': 'team',
      'principalId': t,
      'allow': ['connect'],
      'deny': <String>[],
    },
  ],
  'folderTree': [
    {'orgId': o, 'folderId': f, 'parentId': null},
  ],
  'wrappedKeys': [
    {'folderId': f, 'version': 1, 'meta': env, 'secret': null},
  ],
  'keyHistory': [
    {'folderId': f, 'version': 2, 'meta': env, 'secret': null},
  ],
  'keyRequests': [
    {'orgId': o, 'folderId': f, 'userId': u, 'version': 1, 'secret': true},
  ],
  'pendingRotations': [
    {
      'orgId': o,
      'folderId': f,
      'reason': 'member_removed',
      'removedUserIds': [u],
      'rotatedVersion': null,
    },
  ],
  'itemIds': [f],
};

void main() {
  test('org block round-trips and exposes typed rows', () {
    final b = OrgBlock.fromJson(jsonDecode(jsonEncode(block)));
    expect((b.orgCursor, b.orgs.single.mascot), (12, false));
    expect(
      (
        b.members.first.disabled,
        b.members.last.status,
        b.members.last.publicKey,
        b.members.last.disabled,
      ),
      (true, null, null, null),
    );
    expect(
      (
        b.keyRequests.single.secret,
        b.wrappedKeys.single.keys.version,
        b.keyHistory.single.history.version,
      ),
      (true, 1, 2),
    );
    expect(jsonEncode(b.toJson()), jsonEncode(block));
  });

  test('a missing list is a FormatException, never empty', () {
    for (final key in block.keys) {
      expect(
        () => OrgBlock.fromJson(Map.of(block)..remove(key)),
        throwsFormatException,
        reason: key,
      );
    }
  });

  test(
    'row rules: secret is a bool, key rows carry folderId, ids are uuids',
    () {
      Map<String, Object?> withRow(String list, Map<String, Object?> over) => {
        ...block,
        list: [
          {...((block[list] as List).first as Map<String, Object?>), ...over},
        ],
      };
      for (final bad in [
        withRow('keyRequests', {'secret': 'yes'}),
        withRow('wrappedKeys', {'folderId': null}),
        withRow('keyHistory', {'folderId': 'f'}),
        withRow('members', {'userId': 'u'}),
        withRow('members', {'disabled': 'no'}),
        withRow('orgs', {'settings': <Object?>[]}),
        withRow('acl', {'allow': 'view'}),
        {...block, 'orgCursor': -1},
        {
          ...block,
          'itemIds': ['X'],
        },
      ]) {
        expect(() => OrgBlock.fromJson(bad), throwsFormatException);
      }
    },
  );

  test('sync page with and without org block', () {
    final page = {'items': <Object?>[], 'cursor': 0, 'more': false};
    final p = SyncPage.fromJson(page);
    expect(p.items, isEmpty);
    expect((p.cursor, p.more, p.org), (0, false, null));
    expect(SyncPage.fromJson({...page, 'org': block}).org!.orgCursor, 12);
    expect(
      () => SyncPage.fromJson({...page, 'cursor': -1}),
      throwsFormatException,
    );
    expect(
      () => SyncPage.fromJson({'items': <Object?>[], 'cursor': 0}),
      throwsFormatException,
    );
  });
}
