// SPDX-License-Identifier: Apache-2.0
part of 'settings_screen.dart';

extension _SecurityGroup on _SettingsScreenState {
  List<Widget> _security(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final offline = !(state.sync?.online ?? false);
    final colors = UfColors.of(context);
    return [
      const _AutoLockRow(),
      _BiometricRow(
        available: _biometricAvailable,
        on: _biometricOn,
        onChanged: _setBiometric,
      ),
      SettingRow(
        label: l.settingsChangePassword,
        trailing: OutlinedButton(
          key: const Key('settings-change-password'),
          onPressed: offline ? null : () => _push(const PasswordChangeScreen()),
          child: Text(l.settingsChangePassword),
        ),
      ),
      if (state.serverInfo.has(Flag.recoveryKit))
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
          safetyCode(state.credentials.publicKey),
          style: monoField,
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
}

class _AutoLockRow extends StatelessWidget {
  const _AutoLockRow();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final settings = state.settings;
    return SettingRow(
      label: l.settingsAutoLock,
      trailing: SizedBox(
        width: 160,
        child: UfSelect<int>(
          key: const Key('autolock'),
          value: settings.autoLockMinutes,
          options: [
            for (final m in Settings.autoLockChoices)
              UfOption(
                m,
                m == 0 ? l.autoLockNever : l.autoLockMinutes(m),
                key: Key('autolock-$m'),
              ),
          ],
          onChanged: (v) =>
              state.updateSettings(settings.copyWith(autoLockMinutes: v)),
        ),
      ),
    );
  }
}

class _BiometricRow extends StatelessWidget {
  const _BiometricRow({
    required this.available,
    required this.on,
    required this.onChanged,
  });

  final Future<bool> available;
  final Future<bool> on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FutureBuilder(
      future: Future.wait([available, on]),
      builder: (context, snapshot) {
        final [available, on] = snapshot.data ?? const [false, false];
        if (!available) return const SizedBox.shrink();
        return SettingRow(
          label: l.settingsBiometric,
          hint: l.settingsBiometricBody,
          onTap: () => onChanged(!on),
          trailing: UfSwitch(
            key: const Key('settings-biometric'),
            semanticLabel: l.settingsBiometric,
            value: on,
            onChanged: onChanged,
          ),
        );
      },
    );
  }
}
