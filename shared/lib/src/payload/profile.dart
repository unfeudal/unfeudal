// SPDX-License-Identifier: Apache-2.0
import '../util/json_reader.dart';
import 'payload.dart';

/// Preferences synced through [ProfileMeta.prefs]; others stay per device.
const syncedPrefKeys = [
  'themeMode',
  'terminalTheme',
  'loquetMode',
  'locale',
  'terminalFont',
  'terminalFontSize',
];

class ProfileMeta extends Payload {
  ProfileMeta({
    super.schemaVersion = 1,
    this.displayName,
    this.prefs = const {},
    super.extra = const {},
  });

  factory ProfileMeta.fromJson(Object? json) {
    final r = JsonReader(json, 'profile');
    final prefs = r.opt<Map<String, Object?>>('prefs') ?? const {};
    if (prefs.length > PayloadLimits.prefs) {
      throw const FormatException('profile.prefs: too many keys');
    }
    return ProfileMeta(
      schemaVersion: r.integer('schemaVersion', min: 1),
      displayName: r.optText('displayName', max: PayloadLimits.displayName),
      prefs: prefs,
      extra: r.extra(const {'schemaVersion', 'displayName', 'prefs'}),
    );
  }

  final String? displayName;

  /// Kept as read: unknown or invalid values are ignored by the reader, never dropped.
  final Map<String, Object?> prefs;

  @override
  Map<String, Object?> toJson() => {
    ...extra,
    'schemaVersion': schemaVersion,
    'displayName': displayName,
    if (prefs.isNotEmpty) 'prefs': prefs,
  };
}
