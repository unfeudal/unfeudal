// SPDX-License-Identifier: Apache-2.0
part of 'vault.dart';

/// Host key trust on this device. The sealed ledger's pin wins over the synced knownHost item, so a server
/// can neither revert nor delete a pin; the synced item carries the pin to the user's other devices.
class HostKeyPins {
  HostKeyPins._(this._vault);

  final Vault _vault;

  // The winning knownHost of each host, rebuilt at each reload and write.
  Map<String, ({String id, KnownHostMeta meta})> _synced = {};

  KnownHostMeta? pinOf(String hostId) =>
      _vault.ledger.hostPin(hostId) ?? _synced[hostId]?.meta;

  /// Ledger first (saved), then the winning knownHost item; read-only only skips the sync.
  Future<void> pin(String hostId, String keyType, String fingerprint) async {
    trace(TraceArea.vault, 'pin host key of ${shortId(hostId)}');
    final pin = KnownHostMeta(
      hostItemId: hostId,
      keyType: keyType,
      sha256Fingerprint: fingerprint,
    );
    await _vault.ledger.setHostPin(hostId, pin);
    try {
      await _vault.upsertItem(
        type: 'knownHost',
        id: _synced[hostId]?.id,
        meta: pin.toJson(),
      );
    } on ReadOnlyException {
      // the local pin stands; the synced copy waits for a writable server
    }
  }

  void _rebuild(Iterable<VaultEntry> entries) => _synced = _winners(entries);

  // First sight of a synced pin seeds the ledger; an existing ledger pin is never replaced from the server.
  Future<void> _seed(Iterable<VaultEntry> entries) async {
    final synced = _winners(entries.where((e) => !e.pending));
    for (final MapEntry(key: host, value: pin) in synced.entries) {
      if (_vault.ledger.hostPin(host) != null) continue;
      await _vault.ledger.setHostPin(host, pin.meta);
    }
  }

  /// One knownHost per host: the [winner] among the entries naming it.
  static Map<String, ({String id, KnownHostMeta meta})> _winners(
    Iterable<VaultEntry> entries,
  ) {
    final byHost = <String, List<VaultEntry>>{};
    for (final e in entries) {
      if (e.kind != ItemKind.knownHost || e.state != EntryState.ok) continue;
      byHost
          .putIfAbsent(KnownHostMeta.fromJson(e.meta).hostItemId, () => [])
          .add(e);
    }
    return {
      for (final MapEntry(key: host, value: named) in byHost.entries)
        if (winner(named) case final w?)
          host: (id: w.id, meta: KnownHostMeta.fromJson(w.meta)),
    };
  }
}
