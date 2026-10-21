// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/choices.dart';
import '../../design/dialog.dart';
import '../../design/field.dart';
import '../../design/inputs.dart';
import '../../design/motion.dart';
import '../../design/rows.dart';
import '../../design/tokens.dart';
import '../busy_action.dart';
import 'members_screen.dart';

/// Name, Loquet and retention of an org (admins), then leaving it (anyone) or deleting it (owners). Only changed
/// keys are sent.
class OrgSettingsScreen extends StatefulWidget {
  const OrgSettingsScreen({super.key, required this.orgId});

  final String orgId;

  @override
  State<OrgSettingsScreen> createState() => _OrgSettingsScreenState();
}

class _OrgSettingsScreenState extends State<OrgSettingsScreen> with BusyAction {
  static const _retention = ['auditDays', 'maxVersions', 'trashDays'];
  final _name = TextEditingController();
  final _values = <String, int?>{};
  bool _mascot = true;

  // What the server holds, as last read or saved.
  late Map<String, Object?> _saved;

  // The server's retention values, shown next to each field; null until read.
  Map<String, int>? _server;

  OrgSummary? get _org => AppScope.read(context).orgs?.byId(widget.orgId);

  @override
  void initState() {
    super.initState();
    final org = _org;
    _saved = {
      'name': org?.name ?? '',
      'mascot': org?.isMascotEnabled ?? true,
      for (final k in _retention) k: org?.settings[k],
    };
    _name.text = _saved['name']! as String;
    _mascot = _saved['mascot']! as bool;
    for (final k in _retention) {
      _values[k] = _saved[k] as int?;
    }
    unawaited(_loadRetention());
  }

  // The org's values start the fields; a failed read leaves them as they are, without the server's values.
  Future<void> _loadRetention() async {
    try {
      final r = await AppScope.read(context).api!.orgs.retention(widget.orgId);
      if (!mounted) return;
      setState(() {
        _server = r.server;
        for (final k in _retention) {
          _saved[k] = r.org[k];
          _values[k] = r.org[k];
        }
      });
    } on Exception {
      // the screen stays usable without them
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    final current = <String, Object?>{
      'mascot': _mascot,
      for (final k in _retention) k: _values[k],
    };
    final settings = {
      for (final MapEntry(:key, :value) in current.entries)
        if (_saved[key] != value) key: value,
    };
    final name = _name.text.trim();
    final rename = name.isNotEmpty && name != _saved['name'];
    if (settings.isEmpty && !rename) return;
    await run(() async {
      await state.api!.orgs.update(
        widget.orgId,
        name: rename ? name : null,
        settings: settings.isEmpty ? null : settings,
      );
      _saved = {..._saved, ...current, 'name': rename ? name : _saved['name']};
      await state.sync!.syncNow();
    });
  }

  Future<void> _delete(String name) async {
    final state = AppScope.read(context);
    final yes = await showUfDialog<bool>(
      context,
      alert: true,
      (_) => ConfirmNameDialog(
        name: name,
        title: AppLocalizations.of(context).orgDelete,
        fieldKey: const Key('org-delete-confirm'),
        okKey: const Key('org-delete-ok'),
      ),
    );
    if (yes != true || !mounted) return;
    await run(() async {
      await state.api!.orgs.delete(widget.orgId);
      // the section closes once the org leaves the selection
      state.orgs!.select(null);
      await state.sync!.syncNow();
    });
  }

  Widget _retentionRow(String key, String settingKey, String label) {
    final l = AppLocalizations.of(context);
    return SettingRow(
      label: label,
      hint: switch (_server?[settingKey]) {
        null => null,
        0 => l.orgRetentionUnlimited,
        final days => l.orgRetentionServer(days),
      },
      trailing: UfNumberField(
        key: Key(key),
        value: _values[settingKey],
        width: 96,
        onChanged: (v) => setState(() => _values[settingKey] = v),
      ),
    );
  }

  List<Widget> _adminRows() {
    final l = AppLocalizations.of(context);
    return [
      SettingRow(
        label: l.orgName,
        trailing: SizedBox(
          width: 240,
          child: TextField(
            key: const Key('org-name-field'),
            controller: _name,
            maxLength: 100,
            decoration: const InputDecoration(counterText: ''),
          ),
        ),
      ),
      SettingRow(
        label: l.orgMascot,
        onTap: () => setState(() => _mascot = !_mascot),
        trailing: UfSwitch(
          key: const Key('org-mascot'),
          semanticLabel: l.orgMascot,
          value: _mascot,
          onChanged: (v) => setState(() => _mascot = v),
        ),
      ),
      _retentionRow('org-audit-days', 'auditDays', l.orgAuditDays),
      _retentionRow('org-max-versions', 'maxVersions', l.orgMaxVersions),
      _retentionRow('org-trash-days', 'trashDays', l.orgTrashDays),
      if (problem case final error?)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: UfErrorLine(error),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        child: Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const Key('org-settings-save'),
            onPressed: _save,
            child: Text(l.orgSettingsSave),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final orgs = AppScope.of(context).orgs;
    final org = orgs?.byId(widget.orgId);
    final isAdmin = orgs?.isAdmin(widget.orgId) ?? false;
    final isOwner = orgs?.isOwner(widget.orgId) ?? false;
    // a Material of its own: the section, a dialog or a test may host it
    return Material(
      type: MaterialType.transparency,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (isAdmin) ..._adminRows(),
          SettingRow(
            label: l.orgLeave,
            trailing: TextButton(
              key: const Key('org-leave'),
              style: dangerQuietStyle(colors),
              onPressed: () =>
                  confirmAndLeaveOrg(context, widget.orgId, org?.name ?? ''),
              child: Text(l.orgLeave),
            ),
          ),
          if (isOwner)
            SettingRow(
              label: l.orgDelete,
              trailing: TextButton(
                key: const Key('org-delete'),
                style: dangerQuietStyle(colors),
                onPressed: () => _delete(org!.name),
                child: Text(l.orgDelete),
              ),
            ),
        ],
      ),
    );
  }
}

/// An org deletion: the danger button is enabled only once the exact org name is typed.
class ConfirmNameDialog extends StatefulWidget {
  const ConfirmNameDialog({
    super.key,
    required this.name,
    required this.title,
    required this.fieldKey,
    required this.okKey,
  });

  final String name;
  final String title;
  final Key fieldKey;
  final Key okKey;

  @override
  State<ConfirmNameDialog> createState() => _ConfirmNameDialogState();
}

class _ConfirmNameDialogState extends State<ConfirmNameDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    return UfDialog(
      title: widget.title,
      message: l.orgDeleteConfirm(widget.name),
      actions: [
        CancelButton(onPressed: () => Navigator.pop(context, false)),
        FilledButton(
          key: widget.okKey,
          style: dangerButtonStyle(colors),
          onPressed: _typed.text == widget.name
              ? () => Navigator.pop(context, true)
              : null,
          child: Text(widget.title),
        ),
      ],
      children: [
        TextField(
          key: widget.fieldKey,
          controller: _typed,
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}
