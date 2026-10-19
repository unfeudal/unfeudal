// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';

import '../../design/field.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../settings/settings.dart';
import '../../version.dart';
import '../form_dialog.dart';
import '../import/import_preview_screen.dart';
import '../manage_frame.dart';
import '../onboarding/recovery_kit_view.dart';
import 'delete_account_screen.dart';
import 'export_screen.dart';
import 'password_change_screen.dart';

/// Appearance, language and security of this device, the synced prefs, and the account's safety code.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _displayName = TextEditingController(
    text: AppScope.read(context).vault?.profile.displayName,
  );

  /// Shown only when the hardware, the OS and the server allow it.
  late final Future<bool> _biometricAvailable = AppScope.read(context)
      .biometricAvailable();
  late Future<bool> _biometricOn =
      AppScope.read(context).biometric?.isEnabled() ?? Future.value(false);

  Future<void> _setBiometric(bool on) async {
    final state = AppScope.read(context);
    on ? await state.enableBiometrics() : await state.disableBiometrics();
    if (mounted) {
      final on = state.biometric!.isEnabled();
      setState(() {
        _biometricOn = on;
      });
    }
  }

  @override
  void dispose() {
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _push(Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));

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
    final offline = !(state.sync?.online ?? false);
    final theme = Theme.of(context);
    void update(Settings next) => state.updateSettings(next);
    final forcedOff =
        state.loquet.mode == LoquetMode.off &&
        settings.loquetMode != LoquetMode.off;
    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
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
      void Function(T)? pick,
    ) => Wrap(
      spacing: 8,
      children: [
        for (final (value, key, label) in options)
          ChoiceChip(
            key: Key('$prefix-$key'),
            label: Text(label),
            selected: value == selected,
            onSelected: pick == null ? null : (_) => pick(value),
          ),
      ],
    );
    return ManageFrame(
      title: l.settingsTitle,
      onBack: widget.onBack,
      child: _TwoColumns(
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
            Row(
              spacing: 16,
              children: [
                Flexible(
                  child: UfField(
                    label: l.settingsTerminalFont,
                    child: DropdownButton<String>(
                      key: const Key('terminal-font'),
                      isExpanded: true,
                      value: settings.terminalFont,
                      items: [
                        for (final family in {
                          ..._terminalFonts,
                          settings.terminalFont,
                        })
                          DropdownMenuItem(
                            key: Key('terminal-font-$family'),
                            value: family,
                            child: Text(
                              family == 'JetBrainsMono'
                                  ? 'JetBrains Mono'
                                  : family,
                              style: TextStyle(fontFamily: family),
                            ),
                          ),
                      ],
                      onChanged: (v) =>
                          update(settings.copyWith(terminalFont: v)),
                    ),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: UfField(
                    label: l.settingsTerminalFontSize,
                    child: DropdownButton<int>(
                      key: const Key('terminal-font-size'),
                      value: settings.terminalFontSize,
                      items: [
                        for (var n = 10; n <= 24; n++)
                          DropdownMenuItem(
                            key: Key('terminal-font-size-$n'),
                            value: n,
                            child: Text(n.toString()),
                          ),
                      ],
                      onChanged: (v) =>
                          update(settings.copyWith(terminalFontSize: v)),
                    ),
                  ),
                ),
              ],
            ),
          ]),
          section(l.settingsLoquet, [
            choices<LoquetMode>(
              'loquet-mode',
              [
                (LoquetMode.on, 'on', l.settingsLoquetOn),
                (LoquetMode.sober, 'sober', l.settingsLoquetSober),
                (LoquetMode.off, 'off', l.settingsLoquetOff),
              ],
              settings.loquetMode,
              forcedOff
                  ? null
                  : (v) => update(settings.copyWith(loquetMode: v)),
            ),
            if (forcedOff)
              Text(
                l.settingsLoquetForcedOff,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: UfColors.of(context).muted,
                ),
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
          section(l.settingsSecurity, [
            FutureBuilder(
              future: Future.wait([_biometricAvailable, _biometricOn]),
              builder: (context, snapshot) {
                final [available, on] = snapshot.data ?? const [false, false];
                if (!available) return const SizedBox.shrink();
                return SwitchListTile(
                  key: const Key('settings-biometric'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.settingsBiometric),
                  subtitle: Text(l.settingsBiometricBody),
                  value: on,
                  onChanged: _setBiometric,
                );
              },
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('settings-change-password'),
                  onPressed: offline
                      ? null
                      : () => _push(const PasswordChangeScreen()),
                  child: Text(l.settingsChangePassword),
                ),
                OutlinedButton(
                  key: const Key('settings-security-reset'),
                  onPressed: offline
                      ? null
                      : () => _push(
                          const PasswordChangeScreen(securityReset: true),
                        ),
                  child: Text(l.securityResetTitle),
                ),
                OutlinedButton(
                  key: const Key('settings-export'),
                  onPressed: () => _push(const ExportScreen()),
                  child: Text(l.settingsExport),
                ),
                if (state.serverHas('ssh_config_import'))
                  OutlinedButton(
                    key: const Key('settings-import-ssh-config'),
                    onPressed: () => _push(const ImportPreviewScreen()),
                    child: Text(l.settingsImportSshConfig),
                  ),
                if (!(state.stored?.isInstanceOwner ?? true))
                  TextButton(
                    key: const Key('settings-delete-account'),
                    style: TextButton.styleFrom(
                      foregroundColor: UfColors.of(context).danger,
                    ),
                    onPressed: offline
                        ? null
                        : () => _push(const DeleteAccountScreen()),
                    child: Text(l.settingsDeleteAccount),
                  ),
              ],
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
                  style: TextButton.styleFrom(
                    foregroundColor: UfColors.of(context).danger,
                  ),
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
        padding: EdgeInsets.only(
          bottom: 40,
          right: (constraints.maxWidth - 1100).clamp(0, double.infinity),
        ),
        child: constraints.maxWidth >= 900
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 40,
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

/// The bundled font first, then the platform's monospace families.
List<String> get _terminalFonts => [
  'JetBrainsMono',
  ...switch (defaultTargetPlatform) {
    TargetPlatform.macOS => ['Menlo', 'Monaco', 'SF Mono'],
    TargetPlatform.windows => ['Cascadia Mono', 'Consolas', 'Courier New'],
    _ => const <String>[],
  },
];
