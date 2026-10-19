// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/dialog.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../describe_error.dart';
import '../manage_frame.dart';

/// Name, Loquet and retention of an org (admins); owners can delete it. Only changed keys are sent.
class OrgSettingsScreen extends StatefulWidget {
  const OrgSettingsScreen({super.key, required this.orgId, this.onBack});

  final String orgId;
  final VoidCallback? onBack;

  @override
  State<OrgSettingsScreen> createState() => _OrgSettingsScreenState();
}

class _OrgSettingsScreenState extends State<OrgSettingsScreen> {
  static const _retention = ['auditDays', 'maxVersions', 'trashDays'];
  final _name = TextEditingController();
  final _fields = {for (final k in _retention) k: TextEditingController()};
  bool _mascot = true;

  /// What the server holds, as last read or saved.
  late Map<String, Object?> _saved;

  /// The server's retention values, shown next to each field; null until read.
  Map<String, int>? _server;
  String? _error;

  OrgSummary? get _org =>
      AppScope.read(context).orgs?.orgs
          .where((o) => o.id == widget.orgId)
          .firstOrNull;

  @override
  void initState() {
    super.initState();
    final org = _org;
    _saved = {
      'name': org?.name ?? '',
      'mascot': org?.mascot ?? true,
      for (final k in _retention) k: org?.settings[k],
    };
    _name.text = _saved['name']! as String;
    _mascot = _saved['mascot']! as bool;
    for (final k in _retention) {
      _fields[k]!.text = _saved[k] == null ? '' : '${_saved[k]}';
    }
    _loadRetention();
  }

  /// The org's values start the fields; a failed read leaves them as they are, without the server's values.
  Future<void> _loadRetention() async {
    try {
      final r = await AppScope.read(context).api!.orgRetention(widget.orgId);
      if (!mounted) return;
      final org = {
        'auditDays': r.org.auditDays,
        'maxVersions': r.org.maxVersions,
        'trashDays': r.org.trashDays,
      };
      setState(() {
        _server = {
          'auditDays': r.server.auditDays,
          'maxVersions': r.server.maxVersions,
          'trashDays': r.server.trashDays,
        };
        for (final k in _retention) {
          _saved[k] = org[k];
          _fields[k]!.text = org[k] == null ? '' : '${org[k]}';
        }
      });
    } on Exception {
      // the screen stays usable without them
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final current = <String, Object?>{
      'mascot': _mascot,
      for (final k in _retention) k: int.tryParse(_fields[k]!.text.trim()),
    };
    final settings = {
      for (final MapEntry(:key, :value) in current.entries)
        if (_saved[key] != value) key: value,
    };
    final name = _name.text.trim();
    final rename = name.isNotEmpty && name != _saved['name'];
    if (settings.isEmpty && !rename) return;
    try {
      await state.api!.updateOrg(
        widget.orgId,
        name: rename ? name : null,
        settings: settings.isEmpty ? null : settings,
      );
      _saved = {..._saved, ...current, 'name': rename ? name : _saved['name']};
      await state.sync!.syncNow();
      if (mounted) setState(() => _error = null);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
    }
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
    final l = AppLocalizations.of(context);
    try {
      await state.api!.deleteOrg(widget.orgId);
      state.orgs!.select(null);
      await state.sync!.syncNow();
      widget.onBack?.call();
    } on Exception catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final org = AppScope.of(context).orgs?.orgs
        .where((o) => o.id == widget.orgId)
        .firstOrNull;
    final isOwner = org?.role == OrgRole.owner.name;
    Widget number(String key, String settingKey, String label) => TextField(
      key: Key(key),
      controller: _fields[settingKey],
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        helperText: switch (_server?[settingKey]) {
          null => null,
          0 => l.orgRetentionUnlimited,
          final days => l.orgRetentionServer(days),
        },
      ),
    );
    return ManageFrame(
      title: l.orgSettingsTitle,
      onBack: widget.onBack,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          TextField(
            key: const Key('org-name-field'),
            controller: _name,
            maxLength: 100,
            decoration: InputDecoration(labelText: l.orgName),
          ),
          SwitchListTile(
            key: const Key('org-mascot'),
            contentPadding: EdgeInsets.zero,
            title: Text(l.orgMascot),
            value: _mascot,
            onChanged: (v) => setState(() => _mascot = v),
          ),
          number('org-audit-days', 'auditDays', l.orgAuditDays),
          number('org-max-versions', 'maxVersions', l.orgMaxVersions),
          number('org-trash-days', 'trashDays', l.orgTrashDays),
          if (_error case final error?)
            Text(error, style: TextStyle(color: colors.danger)),
          Row(
            children: [
              if (isOwner)
                TextButton(
                  key: const Key('org-delete'),
                  style: TextButton.styleFrom(foregroundColor: colors.danger),
                  onPressed: () => _delete(org!.name),
                  child: Text(l.orgDelete),
                ),
              const Spacer(),
              FilledButton(
                key: const Key('org-settings-save'),
                onPressed: _save,
                child: Text(l.orgSettingsSave),
              ),
            ],
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
