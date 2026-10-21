// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/settings/settings.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

Future<File> tempSettingsFile() async {
  final dir = await Directory.systemTemp.createTemp('settings');
  addTearDown(() => dir.delete(recursive: true));
  return File('${dir.path}/settings.json');
}

void main() {
  test('defaults', () {
    const s = Settings();
    expect(
      (
        s.themeMode,
        s.terminalTheme,
        s.loquetMode,
        s.locale,
        s.terminalFont,
        s.terminalFontSize,
      ),
      (
        ThemeMode.system,
        TerminalThemeId.charte,
        LoquetMode.on,
        null,
        'JetBrainsMono',
        13,
      ),
    );
    expect(
      (s.performanceMode, s.treeWidth, s.autoLockMinutes),
      (false, 272.0, 15),
    );
  });

  test('toPrefs holds exactly the synced keys', () {
    final p = const Settings(locale: 'fr').toPrefs();
    expect(p.keys.toSet(), syncedPrefKeys.toSet());
    expect(p, {
      'themeMode': 'system',
      'terminalTheme': 'charte',
      'loquetMode': 'on',
      'locale': 'fr',
      'terminalFont': 'JetBrainsMono',
      'terminalFontSize': 13,
    });
    // The default locale follows the system and is not written.
    expect(const Settings().toPrefs().containsKey('locale'), isFalse);
  });

  test('withPrefs applies valid synced values, ignores the rest, never touches device fields', () {
    const base = Settings(
      performanceMode: true,
      treeWidth: 300,
      autoLockMinutes: 5,
    );
    final s = base.withPrefs({
      'themeMode': 'dark',
      'terminalTheme': 'neon',
      'locale': 'de',
      'terminalFontSize': 30,
      'loquetMode': 'sober',
      'futurePref': 1,
      'performanceMode': false,
      'autoLockMinutes': 60,
    });
    expect(
      (
        s.themeMode,
        s.terminalTheme,
        s.locale,
        s.terminalFontSize,
        s.loquetMode,
      ),
      (ThemeMode.dark, TerminalThemeId.charte, null, 13, LoquetMode.sober),
    );
    expect(
      (s.performanceMode, s.treeWidth, s.autoLockMinutes),
      (true, 300.0, 5),
    );
  });

  test('uiLocale: the chosen language, else a supported system language, else null', () {
    expect(const Settings(locale: 'en').uiLocale('fr'), 'en');
    expect(const Settings().uiLocale('fr'), 'fr');
    expect(const Settings().uiLocale('de'), isNull);
  });

  test(
    'prefChangesSince sends every current pref and each removed one as null',
    () {
      final changes = const Settings().prefChangesSince(
        const Settings(locale: 'fr'),
      );
      expect(changes, {...const Settings().toPrefs(), 'locale': null});
    },
  );

  test('withLocale sets and clears the locale, keeping the other fields', () {
    const base = Settings(themeMode: ThemeMode.dark, locale: 'fr');
    final cleared = base.withLocale(null);
    expect((cleared.locale, cleared.themeMode), (null, ThemeMode.dark));
    expect(cleared.withLocale('en').locale, 'en');
  });

  test('per-device ranges', () {
    final s = Settings.fromJson({
      'treeWidth': 900,
      'autoLockMinutes': 7,
      'terminalFontSize': 9,
    });
    expect(
      (s.treeWidth, s.autoLockMinutes, s.terminalFontSize),
      (272.0, 15, 13),
    );
    expect(Settings.autoLockChoices, [0, 5, 15, 30, 60]);
  });

  test('store: a round trip keeps unknown fields', () async {
    final file = await tempSettingsFile();
    final store = SettingsStore(file);
    file.writeAsStringSync('{"future": {"a": 1}, "themeMode": "light"}');
    final s = await store.load();
    expect(s.themeMode, ThemeMode.light);
    await store.save(s.copyWith(autoLockMinutes: 30));
    final saved = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(saved['future'], {'a': 1});
    expect(saved['autoLockMinutes'], 30);
  });

  test('store: save writes atomically, leaving no temporary file', () async {
    final file = await tempSettingsFile();
    await SettingsStore(file).save(const Settings());
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  test('store: a missing or unreadable file gives the defaults', () async {
    final file = await tempSettingsFile();
    final store = SettingsStore(file);
    expect(await store.load(), const Settings());
    file.writeAsStringSync('not json');
    expect(await store.load(), const Settings());
  });

  test('settings.json holds no profile item and no secret', () async {
    final file = await tempSettingsFile();
    await SettingsStore(file)
        .save(const Settings().withPrefs({'themeMode': 'dark'}));
    final keysWritten = (jsonDecode(file.readAsStringSync()) as Map).keys
        .toSet();
    expect(keysWritten, {
      ...syncedPrefKeys.where((k) => k != 'locale'),
      'performanceMode',
      'treeWidth',
      'autoLockMinutes',
    });
  });

  test('settings with the same nested unknown values are equal', () {
    Settings read() => Settings.fromJson({
      'future': {
        'panels': [1, 2],
      },
    });

    expect(read(), read());
    expect(read().hashCode, read().hashCode);
  });
}
