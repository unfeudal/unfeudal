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
  for (final entry in vault.entries) {
    if (entry.item.scope != ItemScope.personal ||
        entry.item.purged ||
        vault.isTrashed(entry.id)) {
      continue;
    }
    final meta = entry.meta;
    if (meta == null ||
        (entry.state != EntryState.ok && entry.state != EntryState.readOnly)) {
      unreadable++;
      continue;
    }
    Map<String, Object?>? secret;
    if (entry.item.secret != null) {
      try {
        secret = (await vault.open(
          entry.item,
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
      'id': entry.id,
      'type': entry.item.type,
      'folderId': entry.item.folderId,
      'meta': meta,
      'secret': secret,
    });
  }
  final text = passphrase == null
      ? VaultExport.plain(items, now: now)
      : await VaultExport.seal(items, passphrase, kdf: kdf, now: now);
  return (text: text, count: items.length, unreadable: unreadable);
}
