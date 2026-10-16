// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'test_server.dart';

/// A sealed wire Item body as a client sends it (no server fields).
/// Personal: keyId `user` with the session's userKey. Org: a throwaway key under the folder keyId
/// (the server checks keyIds, never decrypts).
Future<Map<String, Object?>> testItem(
  TestSession s, {
  String? id,
  String type = 'host',
  String? folderId,
  String scope = 'personal',
  String? orgId,
  int keyVersion = 1,
  bool deleted = false,
  bool secret = false,
  Map<String, Object?> meta = const {'name': 'web'},
}) async {
  final itemId = id ?? newId();
  final itemScope = ItemScope.values.byName(scope);
  Future<Envelope> seal(PayloadPart part, Map<String, Object?> json) {
    final aad = PayloadAad(
      itemId: itemId,
      part: part,
      type: type,
      scope: itemScope,
      orgId: orgId,
      folderId: folderId,
    );
    return itemScope == ItemScope.personal
        ? PayloadCrypto.seal(aad, json, s.account.userKey, KeyIds.user, seq: 1)
        : PayloadCrypto.seal(
            aad,
            json,
            SymmetricCipher.newKey(),
            KeyIds.folder(
              type == 'folder' ? itemId : folderId!,
              keyVersion,
              part,
            ),
            seq: 1,
          );
  }

  return {
    'id': itemId,
    'type': type,
    'scope': scope,
    'orgId': orgId,
    'folderId': folderId,
    'schemaVersion': 1,
    'deleted': deleted,
    'meta': (await seal(PayloadPart.meta, meta)).toJson(),
    'secret': secret
        ? (await seal(PayloadPart.secret, {
            'kind': 'password',
            'password': 'pw',
          })).toJson()
        : null,
  };
}
