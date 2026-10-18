// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';

import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../settings/settings.dart';
import '../../version.dart';
import '../form_dialog.dart';
import '../onboarding/recovery_kit_view.dart';

/// Appearance, language and security of this device, the synced prefs, and the account's safety code.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _displayName = TextEditingController(
    text: AppScope.read(context).vault?.profile.displayName,
  );

  @override
  void dispose() {
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _newRecoveryKit() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    String? key;
    await showUfDialog<bool>(
      context,
      (_) => FormDialog(
        title: l.settingsRecoveryKit,
        fields: [
          FormDialogField(
            'confirm-password',
            l.loginPassword,
            kind: FormFieldKind.secret,
          ),
        ],
        saveKey: 'confirm-password-ok',
        saveLabel: l.settingsRecoveryKit,
        onSave: (v) async =>
            key = await state.regenerateRecoveryKit(v['confirm-password']!),
      ),
    );
    final shown = key;
    if (shown == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (route) => RecoveryKitView(
          recoveryKey: shown,
          onDone: () => Navigator.pop(route),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final settings = state.settings;
    final theme = Theme.of(context);
    void update(Settings next) => state.updateSettings(next);
    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          ...children,
        ],
      ),
    );
    Widget choices<T>(
      String prefix,
      List<(T, String, String)> options,
      T selected,
      void Function(T) pick,
    ) => Wrap(
      spacing: 8,
      children: [
        for (final (value, key, label) in options)
          ChoiceChip(
            key: Key('$prefix-$key'),
            label: Text(label),
            selected: value == selected,
            onSelected: (_) => pick(value),
          ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: _TwoColumns(
        left: [
          section(l.settingsTheme, [
            choices(
              'theme',
              [
                (ThemeMode.system, 'system', l.themeSystem),
                (ThemeMode.light, 'light', l.themeLight),
                (ThemeMode.dark, 'dark', l.themeDark),
              ],
              settings.themeMode,
              (v) => update(settings.copyWith(themeMode: v)),
            ),
          ]),
          section(l.settingsTerminalTheme, [
            choices(
              'terminal-theme',
              [
                (TerminalThemeId.charte, 'charte', l.terminalThemeCharte),
                (
                  TerminalThemeId.solarizedDark,
                  'solarized-dark',
                  l.terminalThemeSolarizedDark,
                ),
                (TerminalThemeId.dracula, 'dracula', l.terminalThemeDracula),
              ],
              settings.terminalTheme,
              (v) => update(settings.copyWith(terminalTheme: v)),
            ),
          ]),
          section(l.settingsLanguage, [
            choices<String?>(
              'language',
              [
                (null, 'system', l.languageSystem),
                ('en', 'en', l.languageEnglish),
                ('fr', 'fr', l.languageFrench),
              ],
              settings.locale,
              (v) => update(
                Settings.fromJson({...settings.toJson(), 'locale': v}),
              ),
            ),
          ]),
          section(l.settingsAutoLock, [
            choices(
              'autolock',
              [
                for (final m in Settings.autoLockChoices)
                  (m, '$m', m == 0 ? l.autoLockNever : l.autoLockMinutes(m)),
              ],
              settings.autoLockMinutes,
              (v) => update(settings.copyWith(autoLockMinutes: v)),
            ),
            SwitchListTile(
              key: const Key('settings-performance'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.settingsPerformance),
              value: settings.performanceMode,
              onChanged: (v) => update(settings.copyWith(performanceMode: v)),
            ),
          ]),
        ],
        right: [
          section(l.settingsDisplayName, [
            TextField(
              key: const Key('settings-display-name'),
              controller: _displayName,
              enabled: !(state.sync?.readOnly ?? true),
              onSubmitted: (v) => state.vault?.setDisplayName(
                v.trim().isEmpty ? null : v.trim(),
              ),
            ),
          ]),
          section(l.settingsSafetyCode, [
            SelectableText(
              safetyCode(state.accountPublicKey),
              style: monoStyle.copyWith(fontSize: 18),
            ),
          ]),
          if (state.serverHas('recovery_kit'))
            section(l.settingsRecoveryKit, [
              Text(l.settingsRecoveryKitBody),
              OutlinedButton(
                key: const Key('settings-recovery-kit'),
                onPressed: (state.sync?.readOnly ?? true)
                    ? null
                    : _newRecoveryKit,
                child: Text(l.settingsRecoveryKit),
              ),
            ]),
          section(l.settingsServer, [
            Text(state.stored?.serverUrl.toString() ?? ''),
            Text(l.settingsVersion(clientVersion, state.serverVersion ?? '?')),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: state.lock,
                  child: Text(l.settingsLockNow),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    await state.signOut();
                  },
                  child: Text(l.settingsSignOut),
                ),
              ],
            ),
          ]),
        ],
      ),
    );
  }
}

/// Appearance on the left and security on the right when the window is wide; one column otherwise.
class _TwoColumns extends StatelessWidget {
  const _TwoColumns({required this.left, required this.right});

  final List<Widget> left;
  final List<Widget> right;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      Widget column(List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: constraints.maxWidth >= 900
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 32,
                children: [
                  Expanded(child: column(left)),
                  Expanded(child: column(right)),
                ],
              )
            : column([...left, ...right]),
      );
    },
  );
}
