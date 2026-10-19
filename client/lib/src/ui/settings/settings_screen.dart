// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';

import '../../design/buttons.dart';
import '../../design/motion.dart';
import '../../design/rows.dart';
import '../../design/tokens.dart';
import '../../settings/settings.dart';
import '../../version.dart';
import '../activity/activity_screen.dart';
import '../admin/instance_admin_screen.dart';
import '../devices/devices_screen.dart';
import '../form_dialog.dart';
import '../import/import_preview_screen.dart';
import '../manage_frame.dart';
import '../onboarding/recovery_kit_view.dart';
import 'delete_account_screen.dart';
import 'export_screen.dart';
import 'licenses_screen.dart';
import 'password_change_screen.dart';

/// Réglages: a group list (appearance, security, devices, data, account, account activity, server, licenses)
/// beside the chosen group's settings.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onBack, this.initialGroup});

  final VoidCallback? onBack;

  /// The group shown first; appearance by default.
  final String? initialGroup;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _group = widget.initialGroup ?? 'appearance';

  late final TextEditingController _displayName;

  @override
  void initState() {
    super.initState();
    _displayName = TextEditingController(
      text: AppScope.read(context).vault?.profile.displayName,
    );
  }

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
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    final groups = [
      ('appearance', l.settingsAppearance),
      ('security', l.settingsSecurity),
      ('devices', l.devicesTitle),
      ('data', l.settingsData),
      ('account', l.settingsAccount),
      if (state.serverHas('audit')) ('activity', l.settingsAccountActivity),
      if (state.stored?.isInstanceOwner ?? false) ('server', l.settingsServer),
      ('licenses', l.settingsLicenses),
    ];
    final group = groups.any((g) => g.$1 == _group) ? _group : 'appearance';
    final label = groups.firstWhere((g) => g.$1 == group).$2;
    // lists that scroll themselves fill the column; the others scroll as one page
    final content = switch (group) {
      'devices' => const DeviceList(),
      'server' => const InstanceAdminPanel(),
      _ => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: switch (group) {
            'security' => _security(context),
            'data' => _data(context),
            'account' => _account(context),
            'activity' => _activity(context),
            'licenses' => _licenses(context),
            _ => _appearance(context),
          },
        ),
      ),
    };
    return ManageFrame(
      title: l.settingsTitle,
      subtitle: l.settingsSubtitle,
      onBack: widget.onBack,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 32,
        children: [
          GroupNav<String>(
            groups: groups,
            current: group,
            onPick: (g) => setState(() => _group = g),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      label,
                      style: text.titleMedium!.copyWith(color: colors.text),
                    ),
                    Expanded(child: content),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A segmented control: one segment per option, each label keyed `$prefix-$key`.
  Widget _choices<T>(
    String prefix,
    List<(T, String, String)> options,
    T selected,
    void Function(T)? pick,
  ) => SegmentedButton<T>(
    key: Key(prefix),
    showSelectedIcon: false,
    segments: [
      for (final (value, key, label) in options)
        ButtonSegment(
          value: value,
          label: Text(label, key: Key('$prefix-$key')),
        ),
    ],
    selected: {selected},
    onSelectionChanged: pick == null ? null : (s) => pick(s.first),
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
          'theme',
          [
            (ThemeMode.system, 'system', l.themeSystem),
            (ThemeMode.light, 'light', l.themeLight),
            (ThemeMode.dark, 'dark', l.themeDark),
          ],
          settings.themeMode,
          (v) => update(settings.copyWith(themeMode: v)),
        ),
      ),
      SettingRow(
        label: l.settingsTerminalTheme,
        trailing: _choices(
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
      ),
      SettingRow(
        label: l.settingsTerminalFont,
        trailing: SizedBox(
          width: 200,
          child: DropdownButton<String>(
            key: const Key('terminal-font'),
            isExpanded: true,
            value: settings.terminalFont,
            items: [
              for (final family in {..._terminalFonts, settings.terminalFont})
                DropdownMenuItem(
                  key: Key('terminal-font-$family'),
                  value: family,
                  child: Text(
                    family == 'JetBrainsMono' ? 'JetBrains Mono' : family,
                    style: TextStyle(fontFamily: family),
                  ),
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
          child: DropdownButton<int>(
            key: const Key('terminal-font-size'),
            isExpanded: true,
            value: settings.terminalFontSize,
            items: [
              for (var n = 10; n <= 24; n++)
                DropdownMenuItem(
                  key: Key('terminal-font-size-$n'),
                  value: n,
                  child: Text(n.toString()),
                ),
            ],
            onChanged: (v) => update(settings.copyWith(terminalFontSize: v)),
          ),
        ),
      ),
      SettingRow(
        label: l.settingsLanguage,
        trailing: _choices<String?>(
          'language',
          [
            (null, 'system', l.languageSystem),
            ('en', 'en', l.languageEnglish),
            ('fr', 'fr', l.languageFrench),
          ],
          settings.locale,
          (v) => update(Settings.fromJson({...settings.toJson(), 'locale': v})),
        ),
      ),
      SettingRow(
        label: l.settingsLoquet,
        hint: forcedOff ? l.settingsLoquetForcedOff : null,
        trailing: _choices<LoquetMode>(
          'loquet-mode',
          [
            (LoquetMode.on, 'on', l.settingsLoquetOn),
            (LoquetMode.sober, 'sober', l.settingsLoquetSober),
            (LoquetMode.off, 'off', l.settingsLoquetOff),
          ],
          settings.loquetMode,
          forcedOff ? null : (v) => update(settings.copyWith(loquetMode: v)),
        ),
      ),
      SettingRow(
        label: l.settingsPerformance,
        trailing: Switch(
          key: const Key('settings-performance'),
          value: settings.performanceMode,
          onChanged: (v) => update(settings.copyWith(performanceMode: v)),
        ),
      ),
    ];
  }

  List<Widget> _security(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final settings = state.settings;
    final offline = !(state.sync?.online ?? false);
    final colors = UfColors.of(context);
    return [
      SettingRow(
        label: l.settingsAutoLock,
        trailing: SizedBox(
          width: 160,
          child: DropdownButton<int>(
            key: const Key('autolock'),
            isExpanded: true,
            value: settings.autoLockMinutes,
            items: [
              for (final m in Settings.autoLockChoices)
                DropdownMenuItem(
                  key: Key('autolock-$m'),
                  value: m,
                  child: Text(m == 0 ? l.autoLockNever : l.autoLockMinutes(m)),
                ),
            ],
            onChanged: (v) =>
                state.updateSettings(settings.copyWith(autoLockMinutes: v)),
          ),
        ),
      ),
      FutureBuilder(
        future: Future.wait([_biometricAvailable, _biometricOn]),
        builder: (context, snapshot) {
          final [available, on] = snapshot.data ?? const [false, false];
          if (!available) return const SizedBox.shrink();
          return SettingRow(
            label: l.settingsBiometric,
            hint: l.settingsBiometricBody,
            trailing: Switch(
              key: const Key('settings-biometric'),
              value: on,
              onChanged: _setBiometric,
            ),
          );
        },
      ),
      SettingRow(
        label: l.settingsChangePassword,
        trailing: OutlinedButton(
          key: const Key('settings-change-password'),
          onPressed: offline ? null : () => _push(const PasswordChangeScreen()),
          child: Text(l.settingsChangePassword),
        ),
      ),
      if (state.serverHas('recovery_kit'))
        SettingRow(
          label: l.settingsRecoveryKit,
          hint: l.settingsRecoveryKitBody,
          trailing: OutlinedButton(
            key: const Key('settings-recovery-kit'),
            onPressed: (state.sync?.readOnly ?? true) ? null : _newRecoveryKit,
            child: Text(l.settingsRecoveryKit),
          ),
        ),
      SettingRow(
        label: l.settingsSafetyCode,
        trailing: SelectableText(
          safetyCode(state.accountPublicKey),
          style: monoStyle.copyWith(fontSize: 14),
        ),
      ),
      SettingRow(
        label: l.securityResetTitle,
        trailing: TextButton(
          key: const Key('settings-security-reset'),
          style: dangerQuietStyle(colors),
          onPressed: offline
              ? null
              : () => _push(const PasswordChangeScreen(securityReset: true)),
          child: Text(l.securityResetTitle),
        ),
      ),
      SettingRow(
        label: l.settingsLockNow,
        trailing: OutlinedButton(
          key: const Key('settings-lock-now'),
          onPressed: state.lock,
          child: Text(l.settingsLockNow),
        ),
      ),
    ];
  }

  List<Widget> _data(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    return [
      if (state.serverHas('ssh_config_import'))
        SettingRow(
          label: l.settingsImportSshConfig,
          trailing: OutlinedButton(
            key: const Key('settings-import-ssh-config'),
            onPressed: () => _push(const ImportPreviewScreen()),
            child: Text(l.settingsImportSshConfig),
          ),
        ),
      SettingRow(
        label: l.settingsExport,
        trailing: OutlinedButton(
          key: const Key('settings-export'),
          onPressed: () => _push(const ExportScreen()),
          child: Text(l.settingsExport),
        ),
      ),
    ];
  }

  List<Widget> _account(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final colors = UfColors.of(context);
    final offline = !(state.sync?.online ?? false);
    return [
      SettingRow(
        label: l.settingsDisplayName,
        hint: state.stored?.email,
        trailing: SizedBox(
          width: 220,
          child: TextField(
            key: const Key('settings-display-name'),
            controller: _displayName,
            enabled: !(state.sync?.readOnly ?? true),
            onSubmitted: (v) =>
                state.vault?.setDisplayName(v.trim().isEmpty ? null : v.trim()),
          ),
        ),
      ),
      SettingRow(
        label: l.settingsSignOut,
        trailing: OutlinedButton(
          key: const Key('settings-sign-out'),
          onPressed: () async {
            Navigator.of(context).popUntil((r) => r.isFirst);
            await state.signOut();
          },
          child: Text(l.settingsSignOut),
        ),
      ),
      if (!(state.stored?.isInstanceOwner ?? true))
        SettingRow(
          label: l.settingsDeleteAccount,
          hint: l.deleteAccountBody,
          trailing: TextButton(
            key: const Key('settings-delete-account'),
            style: dangerQuietStyle(colors),
            onPressed: offline
                ? null
                : () => _push(const DeleteAccountScreen()),
            child: Text(l.settingsDeleteAccount),
          ),
        ),
    ];
  }

  // the activity screen frames itself: it opens on its own, scoped to the account
  List<Widget> _activity(BuildContext context) {
    final l = AppLocalizations.of(context);
    return [
      SettingRow(
        label: l.settingsAccountActivity,
        trailing: OutlinedButton(
          key: const Key('settings-account-activity'),
          onPressed: () => _push(const ActivityScreen(scope: 'user')),
          child: Text(l.activityTitle),
        ),
      ),
    ];
  }

  List<Widget> _licenses(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    return [
      SettingRow(
        label: l.settingsServer,
        hint: l.settingsVersion(clientVersion, state.serverVersion ?? '?'),
        trailing: Text(
          state.stored?.serverUrl.toString() ?? '',
          style: monoStyle.copyWith(fontSize: 13),
        ),
      ),
      SettingRow(
        label: l.settingsLicenses,
        trailing: OutlinedButton(
          key: const Key('settings-licenses'),
          onPressed: () => _push(const LicensesScreen()),
          child: Text(l.settingsLicenses),
        ),
      ),
    ];
  }
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
