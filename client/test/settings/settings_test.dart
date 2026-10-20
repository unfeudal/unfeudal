// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/settings/settings.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

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

  test('store: round trip keeps unknown fields, writes atomically, unreadable gives defaults', () async {
    final dir = await Directory.systemTemp.createTemp('settings');
    final file = File('${dir.path}/settings.json');
    final store = SettingsStore(file);
    expect(await store.load(), const Settings());
    file.writeAsStringSync('{"future": {"a": 1}, "themeMode": "light"}');
    final s = await store.load();
    expect(s.themeMode, ThemeMode.light);
    await store.save(s.copyWith(autoLockMinutes: 30));
    final saved = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(saved['future'], {'a': 1});
    expect(saved['autoLockMinutes'], 30);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
    file.writeAsStringSync('not json');
    expect(await store.load(), const Settings());
  });

  test('settings.json holds no profile item and no secret', () async {
    final dir = await Directory.systemTemp.createTemp('settings');
    final file = File('${dir.path}/settings.json');
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
}
