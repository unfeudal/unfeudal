// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../l10n/app_localizations.dart';

enum LoquetMode { on, sober, off }

enum TerminalThemeId { charte, solarizedDark, dracula }

/// Prefs synced in the profile item, plus per-device settings; [extra] keeps unknown keys.
@immutable
class Settings {
  const Settings({
    this.themeMode = ThemeMode.system,
    this.terminalTheme = TerminalThemeId.charte,
    this.loquetMode = LoquetMode.on,
    this.locale,
    this.terminalFont = 'JetBrainsMono',
    this.terminalFontSize = 13,
    this.performanceMode = false,
    this.treeWidth = 272,
    this.autoLockMinutes = 15,
    this.extra = const {},
  });

  /// Each field is parsed on its own: an invalid value falls back to its default.
  factory Settings.fromJson(Object? json) {
    if (json is! Map<String, Object?>) return const Settings();
    const d = Settings();
    T? byName<T extends Enum>(List<T> values, Object? v) =>
        values.asNameMap()[v];
    return Settings(
      themeMode: byName(ThemeMode.values, json['themeMode']) ?? d.themeMode,
      terminalTheme:
          byName(TerminalThemeId.values, json['terminalTheme']) ??
          d.terminalTheme,
      loquetMode: byName(LoquetMode.values, json['loquetMode']) ?? d.loquetMode,
      locale: switch (json['locale']) {
        final String l when _locales.contains(l) => l,
        _ => null,
      },
      terminalFont: switch (json['terminalFont']) {
        final String f when f.isNotEmpty && f.runes.length <= 64 => f,
        _ => d.terminalFont,
      },
      terminalFontSize: switch (json['terminalFontSize']) {
        final int s when s >= 10 && s <= 24 => s,
        _ => d.terminalFontSize,
      },
      performanceMode: switch (json['performanceMode']) {
        final bool p => p,
        _ => d.performanceMode,
      },
      treeWidth: switch (json['treeWidth']) {
        final num w when w >= 220 && w <= 400 => w.toDouble(),
        _ => d.treeWidth,
      },
      autoLockMinutes: switch (json['autoLockMinutes']) {
        final int m when autoLockChoices.contains(m) => m,
        _ => d.autoLockMinutes,
      },
      extra: {
        for (final MapEntry(:key, :value) in json.entries)
          if (!_known.contains(key)) key: value,
      },
    );
  }

  static const autoLockChoices = [0, 5, 15, 30, 60];
  static const _locales = ['en', 'fr'];
  static const _deviceKeys = [
    'performanceMode',
    'treeWidth',
    'autoLockMinutes',
  ];
  static const _known = {...syncedPrefKeys, ..._deviceKeys};

  final ThemeMode themeMode;
  final TerminalThemeId terminalTheme;
  final LoquetMode loquetMode;

  /// Null follows the system locale.
  final String? locale;
  final String terminalFont;
  final int terminalFontSize;
  final bool performanceMode;
  final double treeWidth;
  final int autoLockMinutes;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    ...extra,
    ...toPrefs(),
    'performanceMode': performanceMode,
    'treeWidth': treeWidth,
    'autoLockMinutes': autoLockMinutes,
  };

  Map<String, Object?> toPrefs() => {
    'themeMode': themeMode.name,
    'terminalTheme': terminalTheme.name,
    'loquetMode': loquetMode.name,
    'locale': ?locale,
    'terminalFont': terminalFont,
    'terminalFontSize': terminalFontSize,
  };

  /// Applies the synced keys of [prefs] that are valid; everything else is ignored.
  Settings withPrefs(Map<String, Object?> prefs) {
    final valid = {
      for (final key in syncedPrefKeys)
        if (prefs.containsKey(key) &&
            Settings.fromJson({key: prefs[key]}).toJson()[key] == prefs[key])
          key: prefs[key],
    };
    return Settings.fromJson({...toJson(), ...valid});
  }

  Settings copyWith({
    ThemeMode? themeMode,
    TerminalThemeId? terminalTheme,
    LoquetMode? loquetMode,
    String? terminalFont,
    int? terminalFontSize,
    bool? performanceMode,
    double? treeWidth,
    int? autoLockMinutes,
  }) => Settings(
    themeMode: themeMode ?? this.themeMode,
    terminalTheme: terminalTheme ?? this.terminalTheme,
    loquetMode: loquetMode ?? this.loquetMode,
    locale: locale,
    terminalFont: terminalFont ?? this.terminalFont,
    terminalFontSize: terminalFontSize ?? this.terminalFontSize,
    performanceMode: performanceMode ?? this.performanceMode,
    treeWidth: treeWidth ?? this.treeWidth,
    autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
    extra: extra,
  );

  /// The chosen language, else the system's when the app has it; null otherwise.
  String? get uiLocale {
    if (locale case final chosen?) return chosen;
    final system = PlatformDispatcher.instance.locale.languageCode;
    return AppLocalizations.supportedLocales.any(
          (l) => l.languageCode == system,
        )
        ? system
        : null;
  }

  @override
  bool operator ==(Object other) =>
      other is Settings && _jsonEquals(other.toJson(), toJson());

  // The keys only: unknown values can be nested maps and lists, which hash by identity.
  @override
  int get hashCode => Object.hashAllUnordered(toJson().keys);
}

// Equality of decoded JSON, nested maps and lists included.
bool _jsonEquals(Object? a, Object? b) => switch ((a, b)) {
  (final Map<Object?, Object?> x, final Map<Object?, Object?> y) =>
    x.length == y.length &&
        x.keys.every((k) => y.containsKey(k) && _jsonEquals(x[k], y[k])),
  (final List<Object?> x, final List<Object?> y) =>
    x.length == y.length && x.indexed.every((e) => _jsonEquals(e.$2, y[e.$1])),
  _ => a == b,
};

/// `settings.json` on this machine: missing or unreadable gives defaults, writes are atomic.
class SettingsStore {
  SettingsStore(this._file);

  final File _file;

  Future<Settings> load() async {
    try {
      return Settings.fromJson(jsonDecode(await _file.readAsString()));
    } on FileSystemException {
      return const Settings();
    } on FormatException {
      return const Settings();
    }
  }

  Future<void> save(Settings settings) async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await tmp.rename(_file.path);
  }
}
