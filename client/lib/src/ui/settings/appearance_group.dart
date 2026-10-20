// SPDX-License-Identifier: Apache-2.0
part of 'settings_screen.dart';

extension _AppearanceGroup on _SettingsScreenState {
  /// A segmented control: one segment per option, each label keyed `$prefix-$key`.
  Widget _choices<T>({
    required String prefix,
    required List<(T, String, String)> options,
    required T selected,
    required void Function(T)? pick,
  }) => UfSegmented<T>(
    key: Key(prefix),
    segments: [
      for (final (value, key, label) in options)
        (value, Text(label, key: Key('$prefix-$key'))),
    ],
    selected: selected,
    onChanged: pick,
  );

  List<Widget> _appearance(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final settings = state.settings;
    void update(Settings next) => state.updateSettings(next);
    final forcedOff =
        state.loquet.mode == LoquetMode.off &&
        settings.loquetMode != LoquetMode.off;
    return [
      SettingRow(
        label: l.settingsTheme,
        trailing: _choices(
          prefix: 'theme',
          options: [
            (ThemeMode.system, 'system', l.themeSystem),
            (ThemeMode.light, 'light', l.themeLight),
            (ThemeMode.dark, 'dark', l.themeDark),
          ],
          selected: settings.themeMode,
          pick: (v) => update(settings.copyWith(themeMode: v)),
        ),
      ),
      ..._terminalRows(l, settings, update),
      SettingRow(
        label: l.settingsLanguage,
        trailing: _choices<String?>(
          prefix: 'language',
          options: [
            (null, 'system', l.languageSystem),
            ('en', 'en', l.languageEnglish),
            ('fr', 'fr', l.languageFrench),
          ],
          selected: settings.locale,
          pick: (v) =>
              update(Settings.fromJson({...settings.toJson(), 'locale': v})),
        ),
      ),
      SettingRow(
        label: l.settingsLoquet,
        hint: forcedOff ? l.settingsLoquetForcedOff : null,
        trailing: _choices<LoquetMode>(
          prefix: 'loquet-mode',
          options: [
            (LoquetMode.on, 'on', l.settingsLoquetOn),
            (LoquetMode.sober, 'sober', l.settingsLoquetSober),
            (LoquetMode.off, 'off', l.settingsLoquetOff),
          ],
          selected: settings.loquetMode,
          pick: forcedOff
              ? null
              : (v) => update(settings.copyWith(loquetMode: v)),
        ),
      ),
      const _PerformanceRow(),
    ];
  }

  List<Widget> _terminalRows(
    AppLocalizations l,
    Settings settings,
    void Function(Settings) update,
  ) => [
    SettingRow(
      label: l.settingsTerminalTheme,
      trailing: _choices(
        prefix: 'terminal-theme',
        options: [
          (TerminalThemeId.charte, 'charte', l.terminalThemeCharte),
          (
            TerminalThemeId.solarizedDark,
            'solarized-dark',
            l.terminalThemeSolarizedDark,
          ),
          (TerminalThemeId.dracula, 'dracula', l.terminalThemeDracula),
        ],
        selected: settings.terminalTheme,
        pick: (v) => update(settings.copyWith(terminalTheme: v)),
      ),
    ),
    SettingRow(
      label: l.settingsTerminalFont,
      trailing: SizedBox(
        width: 200,
        child: UfSelect<String>(
          key: const Key('terminal-font'),
          value: settings.terminalFont,
          options: [
            for (final family in {..._terminalFonts, settings.terminalFont})
              UfOption(
                family,
                family == 'JetBrainsMono' ? 'JetBrains Mono' : family,
                key: Key('terminal-font-$family'),
                style: TextStyle(fontFamily: family),
              ),
          ],
          onChanged: (v) => update(settings.copyWith(terminalFont: v)),
        ),
      ),
    ),
    SettingRow(
      label: l.settingsTerminalFontSize,
      trailing: SizedBox(
        width: 80,
        child: UfSelect<int>(
          key: const Key('terminal-font-size'),
          value: settings.terminalFontSize,
          options: [
            for (var n = 10; n <= 24; n++)
              UfOption(n, n.toString(), key: Key('terminal-font-size-$n')),
          ],
          onChanged: (v) => update(settings.copyWith(terminalFontSize: v)),
        ),
      ),
    ),
  ];
}

class _PerformanceRow extends StatelessWidget {
  const _PerformanceRow();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final settings = state.settings;
    return SettingRow(
      label: l.settingsPerformance,
      onTap: () => state.updateSettings(
        settings.copyWith(performanceMode: !settings.performanceMode),
      ),
      trailing: UfSwitch(
        key: const Key('settings-performance'),
        semanticLabel: l.settingsPerformance,
        value: settings.performanceMode,
        onChanged: (v) =>
            state.updateSettings(settings.copyWith(performanceMode: v)),
      ),
    );
  }
}

// The bundled font first, then the platform's monospace families.
List<String> get _terminalFonts => [
  'JetBrainsMono',
  ...switch (defaultTargetPlatform) {
    TargetPlatform.macOS => ['Menlo', 'Monaco', 'SF Mono'],
    TargetPlatform.windows => ['Cascadia Mono', 'Consolas', 'Courier New'],
    _ => const <String>[],
  },
];
