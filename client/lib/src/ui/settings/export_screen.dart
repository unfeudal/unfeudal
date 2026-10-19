// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/banner.dart';
import '../../design/field.dart';
import '../../design/tokens.dart';
import '../../export/vault_export_service.dart';
import '../busy_action.dart';
import '../manage_frame.dart';
import '../save_file.dart';

/// Exports the personal vault to a file the user picks: encrypted by default, plaintext only once confirmed.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, this.savePath, this.writeFile});

  /// Where to save; a native "Save" dialog by default.
  final Future<String?> Function(String suggestedName)? savePath;
  final Future<void> Function(String path, List<int> bytes)? writeFile;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> with BusyAction {
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();
  bool _plain = false;
  bool _plainConfirmed = false;
  String? _done;

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    if (_plain && !_plainConfirmed) return;
    if (!_plain) {
      if (normalizePassword(_passphrase.text).runes.length <
          VaultExport.minPassphraseLength) {
        return setState(() => problem = l.exportPassphraseShort);
      }
      if (_passphrase.text != _confirm.text) {
        return setState(() => problem = l.passwordsDiffer);
      }
    }
    await run(() async {
      final now = DateTime.now();
      final day = now.toIso8601String().substring(0, 10);
      final path = await (widget.savePath ?? pickSaveLocation)(
        'unfeudal-export-$day.json',
      );
      if (path == null) return;
      final out = await exportVault(
        state.vault!,
        passphrase: _plain ? null : _passphrase.text,
        kdf: state.kdf,
        now: now,
      );
      await (widget.writeFile ?? writeFileBytes)(path, utf8.encode(out.text));
      if (mounted) {
        setState(
          () => _done = [
            l.exportDone(out.count),
            if (out.unreadable > 0) l.exportSkipped(out.unreadable),
          ].join(' '),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    return ManageFrame(
      title: l.settingsExport,
      maxWidth: 520,
      child: ListView(
        shrinkWrap: true,
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                key: const Key('export-encrypted'),
                label: Text(l.exportEncrypted),
                selected: !_plain,
                onSelected: (_) => setState(() => _plain = false),
              ),
              ChoiceChip(
                key: const Key('export-plain'),
                label: Text(l.exportPlain),
                selected: _plain,
                onSelected: (_) => setState(() => _plain = true),
              ),
            ],
          ),
          if (_plain) ...[
            StatusBanner(
              tone: BannerTone.danger,
              message: l.exportPlainWarning,
            ),
            CheckboxListTile(
              key: const Key('export-plain-confirm'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _plainConfirmed,
              onChanged: (v) => setState(() => _plainConfirmed = v ?? false),
              title: Text(l.exportPlainConfirm),
            ),
          ] else ...[
            UfField(
              label: l.exportPassphrase,
              child: TextField(
                key: const Key('export-passphrase'),
                controller: _passphrase,
                obscureText: true,
              ),
            ),
            UfField(
              label: l.exportPassphraseConfirm,
              child: TextField(
                key: const Key('export-passphrase-confirm'),
                controller: _confirm,
                obscureText: true,
              ),
            ),
          ],
          if (problem case final problem?)
            Text(problem, style: TextStyle(color: colors.danger)),
          if (_done case final done?) Text(done),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('export-submit'),
              onPressed: busy ? null : _submit,
              child: Text(l.exportSubmit),
            ),
          ),
        ],
      ),
    );
  }
}
