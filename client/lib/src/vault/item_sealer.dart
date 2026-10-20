// SPDX-License-Identifier: Apache-2.0
part of 'vault.dart';

/// Seals items for the vault's placements without writing them: the caller sends or stores the result.
class ItemSealer {
  ItemSealer._(this._vault);

  final Vault _vault;

  /// One seq for both parts, keyId `user`, the AAD of the new placement.
  Future<Item> seal({
    required String id,
    required String type,
    String? folderId,
    bool deleted = false,
    int revision = 0,
    required Map<String, Object?> meta,
    Map<String, Object?>? secret,
  }) => sealItem(
    id: id,
    type: type,
    folderId: folderId,
    deleted: deleted,
    revision: revision,
    meta: meta,
    secret: secret,
    keyFor: _vault._personal.sealKeys(
      type: type,
      id: id,
      folderId: folderId,
      withSecret: secret != null,
    ),
  );

  /// Both parts sealed by [keyFor] with the next seq of [id], keeping what the current item carries.
  Future<Item> sealItem({
    required String id,
    required String type,
    String? orgId,
    String? folderId,
    bool deleted = false,
    int revision = 0,
    required Map<String, Object?> meta,
    Map<String, Object?>? secret,
    required SealKeys keyFor,
  }) => sealPayloads(
    current: _vault._entries[id]?.item,
    id: id,
    type: type,
    orgId: orgId,
    folderId: folderId,
    deleted: deleted,
    revision: revision,
    seq: _vault.ledger.nextSeq(id),
    meta: meta,
    secret: secret,
    keyFor: keyFor,
  );

  /// A copy of [mine] in [orgId]'s [folderId] under a new id at revision 0, both parts opened and sealed
  /// by [scope], the name suffixed. Null for an unknown type.
  Future<Item?> conflictCopyIn(
    WriteScope scope,
    Item mine, {
    required String suffix,
    String? orgId,
    String? folderId,
  }) async {
    final parts = await conflictCopyParts(
      mine,
      suffix,
      (part) => scope.openPart(mine, part, fromServer: false),
    );
    if (parts == null) return null;
    final id = newId();
    return sealItem(
      id: id,
      type: mine.type,
      orgId: orgId,
      folderId: folderId,
      meta: parts.meta,
      secret: parts.secret,
      keyFor: scope.sealKeys(
        type: mine.type,
        id: id,
        folderId: folderId,
        withSecret: parts.secret != null,
      ),
    );
  }
}
