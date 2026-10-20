// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

const names = [
  'api_info',
  'item_host',
  'item_unknown_type',
  'item_tombstone',
  'payload_host',
  'payload_folder',
  'payload_identity',
  'payload_profile',
  'payload_snippet',
  'error_conflict',
  'account_bundle',
  'enrollment_encrypted',
];

/// Formats this side only reads: there is no writer to round-trip through.
const readOnly = {'error_conflict', 'enrollment_encrypted'};

Map<String, Object?> Function(Object?) parserFor(String name) => switch (name) {
  'api_info' => (j) => ApiInfo.fromJson(j).toJson(),
  _ when name.startsWith('item_') => (j) => Item.fromJson(j).toJson(),
  'payload_host' => (j) => HostMeta.fromJson(j).toJson(),
  'payload_folder' => (j) => FolderMeta.fromJson(j).toJson(),
  'payload_identity' => (j) => IdentityMeta.fromJson(j).toJson(),
  'payload_profile' => (j) => ProfileMeta.fromJson(j).toJson(),
  'payload_snippet' => (j) => SnippetMeta.fromJson(j).toJson(),
  'account_bundle' => (j) => AccountBundle.fromJson(j).toJson(),
  _ => throw StateError('no parser for $name'),
};

void main() {
  final dir = Directory('test/fixtures');

  test('v0 holds exactly the fixed list', () {
    final found = Directory('${dir.path}/v0')
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .toSet();
    expect(found, {for (final n in names) '$n.json'});
  });

  for (final file
      in dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))) {
    final name = file.uri.pathSegments.last.replaceAll('.json', '');
    if (readOnly.contains(name)) continue;
    test('${file.path} re-serialises byte for byte', () {
      final text = file.readAsStringSync().trim();
      expect(jsonEncode(parserFor(name)(jsonDecode(text))), text);
    });
  }

  test('error_conflict parses', () {
    final body = ApiErrorBody.fromJson(
      jsonDecode(File('${dir.path}/v0/error_conflict.json').readAsStringSync()),
    );
    expect(
      (body.error, body.message, body.item!.revision, body.extra.isEmpty),
      ('conflict', 'Revision mismatch.', 4, true),
    );
  });

  test('only item_host carries a top-level unknown field', () {
    final host = jsonDecode(
      File('${dir.path}/v0/item_host.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(Item.fromJson(host).extra.keys, ['pinnedBy']);
    final other = jsonDecode(
      File('${dir.path}/v0/item_unknown_type.json').readAsStringSync(),
    );
    expect(Item.fromJson(other).extra, isEmpty);
    expect(
      ApiInfo.fromJson(
        jsonDecode(File('${dir.path}/v0/api_info.json').readAsStringSync()),
      ).extra,
      isEmpty,
    );
  });

  test('account bundle fixture unlocks with its password', () async {
    final bundle = AccountBundle.fromJson(
      jsonDecode(File('${dir.path}/v0/account_bundle.json').readAsStringSync()),
    );
    final u = await AccountCrypto(
      kdf: KdfParams.testing,
      kdfFloor: KdfParams.testing,
    ).unlock(bundle, 'fixture-password');
    expect(u.userKey.length, 32);
  });
}
