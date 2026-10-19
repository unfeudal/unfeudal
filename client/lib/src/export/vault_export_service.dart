// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../vault/vault.dart';

/// The personal, live items of the vault as an export file: sealed with [passphrase], or plaintext without one.
Future<({String text, int count, int unreadable})> exportVault(
  Vault vault, {
  String? passphrase,
  KdfParams kdf = KdfParams.defaults,
  DateTime? now,
}) async {
  final items = <Map<String, Object?>>[];
  var unreadable = 0;
  for (final e in vault.entries) {
    if (e.item.scope != ItemScope.personal ||
        e.item.purged ||
        vault.isTrashed(e.id)) {
      continue; // personal, live items only
    }
    final meta = e.meta;
    if (meta == null ||
        (e.state != EntryState.ok && e.state != EntryState.readOnly)) {
      unreadable++;
      continue;
    }
    Map<String, Object?>? secret;
    if (e.item.secret != null) {
      try {
        secret = (await vault.open(
          e.item,
          PayloadPart.secret,
          fromServer: false,
        ))?.json;
      } on Exception {
        secret = null;
      }
      if (secret == null) {
        unreadable++;
        continue;
      }
    }
    items.add({
      'id': e.id,
      'type': e.item.type,
      'folderId': e.item.folderId,
      'meta': meta,
      'secret': secret,
    });
  }
  final text = passphrase == null
      ? VaultExport.plain(items, now: now)
      : await VaultExport.seal(items, passphrase, kdf: kdf, now: now);
  return (text: text, count: items.length, unreadable: unreadable);
}
