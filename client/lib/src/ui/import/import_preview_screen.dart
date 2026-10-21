// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/banner.dart';
import '../../design/buttons.dart';
import '../../design/choices.dart';
import '../../design/empty_state.dart';
import '../../design/feedback.dart';
import '../../design/field.dart';
import '../../design/rows.dart';
import '../../design/toast.dart';
import '../../import/ssh_config_import.dart';
import '../busy_action.dart';
import '../describe_error.dart';
import '../fields.dart';
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

class _ImportPreviewScreenState extends State<ImportPreviewScreen>
    with BusyAction {
  late final SshConfigImporter _importer;
  ImportPlan? _plan;
  final _selected = <String>{};
  final _passphrases = <String, TextEditingController>{};
  String? _folderId;

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
    unawaited(_load(readFile, widget.configPath ?? '$home/.ssh/config'));
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
    return file.existsSync() ? file.readAsString() : null;
  }

  Future<void> _load(
    Future<String?> Function(String path) readFile,
    String configPath,
  ) async {
    final ImportPlan plan;
    try {
      plan = await _importer.plan(await readFile(configPath) ?? '');
    } on FileSystemException catch (e) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      return setState(() => problem = describeError(l, e));
    }
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _selected.addAll([
        for (final h in plan.hosts)
          if (!h.isDuplicate) h.source.alias,
      ]);
      for (final k in plan.keys.where((k) => k.needsPassphrase)) {
        _passphrases[k.path] = TextEditingController();
      }
    });
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    await run(() async {
      final (:written, :warnings) = await _importer.apply(
        _plan!,
        aliases: _selected,
        passphrases: {
          for (final MapEntry(:key, :value) in _passphrases.entries)
            key: value.text,
        },
        folderId: _folderId,
      );
      if (!mounted) return;
      showUfToast(
        context,
        [
          l.importDone(written),
          for (final w in warnings)
            l.importWarning(w.line, _problemLabel(l, w.kind)),
        ].join('\n'),
        tone: warnings.isEmpty ? UfToastTone.ok : UfToastTone.warn,
      );
      Navigator.of(context).maybePop();
    });
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
    final plan = _plan;
    // a Scaffold of its own: pushed alone, the confirmation still has somewhere to show
    return Scaffold(
      body: ManageFrame(
        title: l.settingsImportSshConfig,
        child: plan == null
            ? switch (problem) {
                final problem? => UfErrorLine(problem),
                null => Center(child: UfLoading(l.loading)),
              }
            : plan.hosts.isEmpty && plan.warnings.isEmpty
            ? EmptyState(title: l.settingsImportSshConfig, body: l.importEmpty)
            : _preview(l, plan),
      ),
    );
  }

  Widget _preview(AppLocalizations l, ImportPlan plan) {
    final state = AppScope.read(context);
    return ListView(
      children: [
        if (plan.warnings.isNotEmpty)
          UfNotice(
            tone: BannerTone.warn,
            message: [
              for (final w in plan.warnings)
                l.importWarning(w.line, _problemLabel(l, w.kind)),
            ].join('\n'),
          ),
        for (final h in plan.hosts)
          _ImportHostRow(
            host: h,
            selected: _selected.contains(h.source.alias),
            onChanged: (on) => setState(
              () => on
                  ? _selected.add(h.source.alias)
                  : _selected.remove(h.source.alias),
            ),
          ),
        for (final (i, k) in plan.keys.indexed)
          if (_passphrases[k.path] case final controller?)
            keyedField(
              'import-passphrase-$i',
              controller,
              l.importPassphrase(p.basename(k.path)),
              secret: true,
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
        if (problem case final problem?) UfErrorLine(problem),
        Align(
          alignment: Alignment.centerRight,
          child: BusyButton(
            key: const Key('import-submit'),
            busy: busy,
            onPressed: _selected.isEmpty || (state.sync?.isReadOnly ?? false)
                ? null
                : _submit,
            label: l.importCount(_selected.length),
          ),
        ),
      ],
    );
  }
}

class _ImportHostRow extends StatelessWidget {
  const _ImportHostRow({
    required this.host,
    required this.selected,
    required this.onChanged,
  });

  final PlannedHost host;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final source = host.source;
    final target = [?source.user, source.hostName ?? source.alias].join('@');
    return UfCheckboxRow(
      key: Key('import-row-${source.alias}'),
      value: selected,
      onChanged: onChanged,
      label: source.alias,
      subtitle: [
        if (host.jumpAlias case final jump?)
          l.statusVia(target, jump)
        else
          target,
        if (host.isDuplicate) l.importDuplicate,
      ].join(l.listSeparator),
    );
  }
}
