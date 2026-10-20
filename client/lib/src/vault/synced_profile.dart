// SPDX-License-Identifier: Apache-2.0
part of 'vault.dart';

/// The display name and synced prefs. The `ok` profile with the smallest id wins on every device; with none,
/// an empty profile.
class SyncedProfile {
  SyncedProfile._(this._vault);

  final Vault _vault;

  ProfileMeta get meta => switch (_entry) {
    final VaultEntry e => ProfileMeta.fromJson(e.meta),
    null => ProfileMeta(),
  };

  /// Merges into the winning profile's prefs: null removes a key, unknown keys stay.
  Future<void> setPrefs(Map<String, Object?> changes) {
    final prefs = {...meta.prefs};
    for (final MapEntry(:key, :value) in changes.entries) {
      value == null ? prefs.remove(key) : prefs[key] = value;
    }
    return _update(displayName: meta.displayName, prefs: prefs);
  }

  Future<void> setDisplayName(String? name) =>
      _update(displayName: name, prefs: meta.prefs);

  VaultEntry? get _entry =>
      winner(_vault._entries.values.where((e) => e.kind == ItemKind.profile));

  Future<void> _update({
    required String? displayName,
    required Map<String, Object?> prefs,
  }) {
    final current = meta;
    return _vault.upsertItem(
      type: 'profile',
      id: _entry?.id,
      meta: ProfileMeta(
        schemaVersion: current.schemaVersion,
        displayName: displayName,
        prefs: prefs,
        extra: current.extra,
      ).toJson(),
    );
  }
}
