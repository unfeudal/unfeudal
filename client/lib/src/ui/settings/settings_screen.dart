// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/buttons.dart';
import '../../design/choices.dart';
import '../../design/motion.dart';
import '../../design/rows.dart';
import '../../design/segmented.dart';
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

part 'appearance_group.dart';
part 'security_group.dart';

/// Settings: a group list (appearance, security, devices, data, account, account activity, server, licenses)
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
      text: AppScope.read(context).vault?.profile.meta.displayName,
    );
  }

  // Shown only when the hardware, the OS and the server allow it.
  late final Future<bool> _biometricAvailable =
      AppScope.read(context).biometrics?.isAvailable() ?? Future.value(false);
  late Future<bool> _biometricOn =
      AppScope.read(context).biometrics?.isEnabled() ?? Future.value(false);

  Future<void> _setBiometric(bool on) async {
    final state = AppScope.read(context);
    on ? await state.enableBiometrics() : await state.biometrics?.disable();
    if (mounted) {
      final on = state.biometrics!.isEnabled();
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
        onSave: (v) async => key = await state.credentials
            .regenerateRecoveryKit(v['confirm-password']!),
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
    final groups = [
      ('appearance', l.settingsAppearance),
      ('security', l.settingsSecurity),
      ('devices', l.devicesTitle),
      ('data', l.settingsData),
      ('account', l.settingsAccount),
      if (state.serverInfo.has(Flag.audit))
        ('activity', l.settingsAccountActivity),
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
            child: _GroupPane(label: label, content: content),
          ),
        ],
      ),
    );
  }

  List<Widget> _data(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    return [
      if (state.serverInfo.has(Flag.sshConfigImport))
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
            onSubmitted: (v) => state.vault?.profile.setDisplayName(
              v.trim().isEmpty ? null : v.trim(),
            ),
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
        hint: l.settingsVersion(clientVersion, state.serverInfo.version ?? '?'),
        trailing: Text(
          state.stored?.serverUrl.toString() ?? '',
          style: monoField,
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

class _GroupPane extends StatelessWidget {
  const _GroupPane({required this.label, required this.content});

  final String label;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: text.titleMedium!.copyWith(color: colors.text)),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}
