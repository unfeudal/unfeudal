// SPDX-License-Identifier: Apache-2.0
part of 'vault.dart';

// Personal items: the user key, no permission check, replay-checked opens.
class _PersonalScope implements WriteScope {
  _PersonalScope(this._vault);
  final Vault _vault;

  @override
  void checkWrite(
    VaultEntry? current, {
    required String type,
    required String? orgId,
    required String? folderId,
  }) {
    _vault._requireKey();
    if (current != null) _requireRewritable(current);
  }

  @override
  void checkDelete(VaultEntry current) => _requireRewritable(current);

  @override
  Future<Map<String, Object?>> openPart(
    Item item,
    PayloadPart part, {
    required bool fromServer,
  }) async {
    final opened = await _vault.open(item, part, fromServer: fromServer);
    if (opened == null) throw const _ReplayedSecret();
    return opened.json;
  }

  @override
  SealKeys sealKeys({
    required String type,
    required String id,
    required String? folderId,
    required bool withSecret,
  }) {
    final key = _vault._requireKey();
    return (_) => (key: key, keyId: KeyIds.user);
  }
}

class _ReplayedSecret implements Exception {
  const _ReplayedSecret();
}

class _MissingFolderKey implements Exception {
  const _MissingFolderKey();
}
