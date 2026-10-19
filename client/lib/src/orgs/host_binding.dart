// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../vault/vault.dart';

/// A `perMember` org host has no personal key bound on this account.
class MissingBinding implements Exception {
  const MissingBinding(this.hostId);
  final String hostId;
}

/// The personal identity bound to [hostId]: the `ok` binding with the smallest id, when its identity is personal and ok.
String? bindingFor(Vault vault, String hostId) {
  final identityId = _bindingOf(vault, hostId)?.$2.identityId;
  final identity = identityId == null ? null : vault.entry(identityId);
  return identity != null &&
          identity.state == EntryState.ok &&
          identity.kind == ItemKind.identity &&
          identity.orgId == null
      ? identityId
      : null;
}

/// Updates the host's binding in place, else writes a new personal one; the org never sees it.
Future<void> bindHost(Vault vault, String hostId, String identityId) =>
    vault.upsertItem(
      type: 'hostBinding',
      id: _bindingOf(vault, hostId)?.$1.id,
      meta: HostBindingMeta(
        hostItemId: hostId,
        identityId: identityId,
      ).toJson(),
    );

(VaultEntry, HostBindingMeta)? _bindingOf(Vault vault, String hostId) {
  final bindings =
      [
          for (final e in vault.ofKind(ItemKind.hostBinding))
            if (e.state == EntryState.ok && e.orgId == null)
              (e, HostBindingMeta.fromJson(e.meta)),
        ].where((b) => b.$2.hostItemId == hostId).toList()
        ..sort((a, b) => a.$1.id.compareTo(b.$1.id));
  return bindings.firstOrNull;
}
