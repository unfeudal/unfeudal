// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/banner.dart';
import '../../design/empty_state.dart';
import '../../design/tokens.dart';
import '../../import/ssh_config_import.dart';
import '../describe_error.dart';
import '../hosts/editor_frame.dart';
import '../manage_frame.dart';

/// Previews a `~/.ssh/config`: the user picks the hosts, gives key passphrases and a target folder.
class ImportPreviewScreen extends StatefulWidget {
  const ImportPreviewScreen({
    super.key,
    this.configPath,
    this.home,
    this.readFile,
  });

  final String? configPath;
  final String? home;
  final Future<String?> Function(String path)? readFile;

  @override
  State<ImportPreviewScreen> createState() => _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends State<ImportPreviewScreen> {
  late final SshConfigImporter _importer;
  ImportPlan? _plan;
  final _selected = <String>{};
  final _passphrases = <String, TextEditingController>{};
  String? _folderId;
  bool _busy = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    final home =
        widget.home ??
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    final readFile = widget.readFile ?? _readOrNull;
    _importer = SshConfigImporter(
      AppScope.read(context).vault!,
      readFile: readFile,
      home: home,
    );
    _load(readFile, widget.configPath ?? '$home/.ssh/config');
  }

  @override
  void dispose() {
    for (final c in _passphrases.values) {
      c.dispose();
    }
    super.dispose();
  }

  static Future<String?> _readOrNull(String path) async {
    final file = File(path);
    return await file.exists() ? file.readAsString() : null;
  }

  Future<void> _load(
    Future<String?> Function(String path) readFile,
    String configPath,
  ) async {
    final plan = await _importer.plan(await readFile(configPath) ?? '');
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _selected.addAll([
        for (final h in plan.hosts)
          if (!h.duplicate) h.source.alias,
      ]);
      for (final k in plan.keys.where((k) => k.needsPassphrase)) {
        _passphrases[k.path] = TextEditingController();
      }
    });
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final count = await _importer.apply(
        _plan!,
        aliases: _selected,
        passphrases: {
          for (final MapEntry(:key, :value) in _passphrases.entries)
            key: value.text,
        },
        folderId: _folderId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.importDone(count))));
      Navigator.of(context).maybePop();
    } on Exception catch (e) {
      if (mounted) setState(() => _problem = describeError(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _problemLabel(AppLocalizations l, SshConfigWarningKind kind) =>
      switch (kind) {
        SshConfigWarningKind.include => l.importProblemInclude,
        SshConfigWarningKind.match => l.importProblemMatch,
        SshConfigWarningKind.unsupported => l.importProblemUnsupported,
        SshConfigWarningKind.badValue => l.importProblemBadValue,
        SshConfigWarningKind.jumpUnresolved => l.importProblemJumpUnresolved,
        SshConfigWarningKind.jumpLoop => l.importProblemJumpLoop,
        SshConfigWarningKind.keyUnreadable => l.importProblemKeyUnreadable,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final colors = UfColors.of(context);
    final plan = _plan;
    // a Scaffold of its own: pushed alone, the confirmation still has somewhere to show
    return Scaffold(
      body: ManageFrame(
        title: l.settingsImportSshConfig,
        child: plan == null
            ? const Center(child: CircularProgressIndicator())
            : plan.hosts.isEmpty && plan.warnings.isEmpty
            ? EmptyState(title: l.settingsImportSshConfig, body: l.importEmpty)
            : ListView(
                children: [
                  if (plan.warnings.isNotEmpty)
                    StatusBanner(
                      tone: BannerTone.warn,
                      message: [
                        for (final w in plan.warnings)
                          l.importWarning(w.line, _problemLabel(l, w.kind)),
                      ].join('\n'),
                    ),
                  for (final h in plan.hosts)
                    CheckboxListTile(
                      key: Key('import-row-${h.source.alias}'),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _selected.contains(h.source.alias),
                      onChanged: (on) => setState(
                        () => on == true
                            ? _selected.add(h.source.alias)
                            : _selected.remove(h.source.alias),
                      ),
                      title: Text(h.source.alias),
                      subtitle: Text(
                        [
                          [
                            ?h.source.user,
                            h.source.hostName ?? h.source.alias,
                          ].join('@'),
                          if (h.jumpAlias case final jump?) '→ $jump',
                          if (h.duplicate) l.importDuplicate,
                        ].join('  ·  '),
                      ),
                    ),
                  for (final (i, k) in plan.keys.indexed)
                    if (_passphrases[k.path] case final controller?)
                      TextField(
                        key: Key('import-passphrase-$i'),
                        controller: controller,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l.importPassphrase(p.basename(k.path)),
                        ),
                      ),
                  entryPicker(
                    key: 'import-folder',
                    label: l.hostFolder,
                    none: l.folderRoot,
                    entries: [
                      for (final e in state.vault!.ofKind(ItemKind.folder))
                        if (e.orgId == null) e,
                    ],
                    value: _folderId,
                    onChanged: (v) => setState(() => _folderId = v),
                  ),
                  if (_problem case final problem?)
                    Text(problem, style: TextStyle(color: colors.danger)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const Key('import-submit'),
                      onPressed:
                          _busy ||
                              _selected.isEmpty ||
                              (state.sync?.readOnly ?? false)
                          ? null
                          : _submit,
                      child: Text(l.importCount(_selected.length)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
