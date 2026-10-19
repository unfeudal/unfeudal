// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../audit/activity_model.dart';
import '../../audit/audit_anchors.dart';
import '../../design/banner.dart';
import '../../design/empty_state.dart';
import '../../design/tokens.dart';
import '../describe_error.dart';
import '../manage_frame.dart';

/// The audit views this account may read: its actions and chain, org chains it administers, folders it
/// manages, the instance for the Instance Owner. Verify and export read the whole chain.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({
    super.key,
    this.scope = 'me',
    this.savePath,
    this.writeFile,
    this.onBack,
  });

  final String scope;

  /// Where to save an export; a native "Save" dialog by default.
  final Future<String?> Function(String suggestedName)? savePath;
  final Future<void> Function(String path, List<int> bytes)? writeFile;
  final VoidCallback? onBack;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late String _scope = widget.scope;
  late ActivityModel _model = _open(_scope);
  String? _notice;

  ActivityModel _open(String scope) {
    final state = AppScope.read(context);
    return ActivityModel(
      api: state.api!,
      anchors: AuditAnchors(state.mirror!),
      userId: state.stored!.userId,
      scope: scope,
    )..load();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  void _select(String scope) {
    _model.dispose();
    setState(() {
      _scope = scope;
      _model = _open(scope);
      _notice = null;
    });
  }

  /// (scope, label) pairs offered to this account.
  List<(String, String)> _scopes(AppLocalizations l, AppState state) {
    final block = state.orgs?.block;
    return [
      ('me', l.activityScopeMe),
      ('user', l.activityScopeAccount),
      for (final org in block?.orgs ?? const <OrgSummary>[])
        if (state.orgs!.isAdmin(org.id))
          ('org:${org.id}', org.name)
        else
          for (final n in block!.folderTree)
            if (n.orgId == org.id &&
                state.orgs!
                    .permissions(org.id, n.folderId)
                    .contains(Permission.manage))
              (
                'folder:${n.folderId}',
                l.activityScopeFolder(
                  state.vault?.entry(n.folderId)?.name ??
                      n.folderId.substring(0, 8),
                ),
              ),
      if (state.stored!.isInstanceOwner) ('instance', l.activityScopeInstance),
    ];
  }

  /// Ids only travel: items, members and orgs are named from what this device holds.
  String Function(String) _resolver(AppLocalizations l, AppState state) {
    final block = state.orgs?.block;
    return (id) {
      if (id == 'root') return l.activityRoot;
      if (id.startsWith('forward:')) return id.substring(8);
      if (id == state.stored!.userId) return l.activityYou;
      return state.vault?.entry(id)?.name ??
          block?.members.where((m) => m.userId == id).firstOrNull?.email ??
          block?.orgs.where((o) => o.id == id).firstOrNull?.name ??
          (id.length > 8 ? id.substring(0, 8) : id);
    };
  }

  Future<void> _verify() async {
    final l = AppLocalizations.of(context);
    try {
      final chain = await _model.wholeChain();
      final report = verifyChain(chain);
      final count = chain.length;
      if (!mounted) return;
      setState(
        () => _notice = report.ok
            ? l.activityVerified(count)
            : l.activityBroken(report.brokenAt!),
      );
    } on Exception catch (e) {
      if (mounted) setState(() => _notice = describeError(l, e));
    }
  }

  Future<void> _export() async {
    final l = AppLocalizations.of(context);
    final chain = ActivityModel.chainOf(_scope)!;
    try {
      final path = await (widget.savePath ?? _pickSaveLocation)(
        ActivityModel.exportFileName(chain),
      );
      if (path == null) return;
      await (widget.writeFile ?? _write)(
        path,
        utf8.encode(await _model.exportJson()),
      );
      if (mounted) setState(() => _notice = l.activityExported(path));
    } on Exception catch (e) {
      if (mounted) setState(() => _notice = describeError(l, e));
    }
  }

  static Future<String?> _pickSaveLocation(String suggestedName) async =>
      (await getSaveLocation(suggestedName: suggestedName))?.path;

  static Future<void> _write(String path, List<int> bytes) =>
      File(path).writeAsBytes(bytes);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final state = AppScope.of(context);
    final scopes = _scopes(l, state);
    final chain = ActivityModel.chainOf(_scope);
    final nameOf = _resolver(l, state);
    final dates = MaterialLocalizations.of(context);
    final muted = TextStyle(color: colors.muted, fontSize: 12);
    return ManageFrame(
      title: l.activityTitle,
      onBack: widget.onBack,
      child: ListenableBuilder(
        listenable: _model,
        builder: (context, _) {
          final m = _model;
          final alert = m.alerts.firstOrNull;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Row(
                spacing: 8,
                children: [
                  DropdownButton<String>(
                    key: const Key('activity-scope'),
                    value: scopes.any((s) => s.$1 == _scope) ? _scope : null,
                    items: [
                      for (final (scope, label) in scopes)
                        DropdownMenuItem(
                          key: Key('activity-scope-$scope'),
                          value: scope,
                          child: Text(label),
                        ),
                    ],
                    onChanged: (s) {
                      if (s != null && s != _scope) _select(s);
                    },
                  ),
                  const Spacer(),
                  if (chain != null) ...[
                    TextButton(
                      key: const Key('activity-verify'),
                      onPressed: _verify,
                      child: Text(l.activityVerify),
                    ),
                    TextButton(
                      key: const Key('activity-export'),
                      onPressed: _export,
                      child: Text(l.activityExport),
                    ),
                  ],
                ],
              ),
              if (alert != null)
                StatusBanner(
                  key: const Key('activity-alert'),
                  tone: BannerTone.danger,
                  message: alert.kind == AnchorAlertKind.rewritten
                      ? l.activityRewritten(alert.scope, alert.seq)
                      : l.activityVanished(alert.scope, alert.seq),
                ),
              if (m.error case final Exception e)
                StatusBanner(
                  tone: BannerTone.warn,
                  message: describeError(l, e),
                ),
              if (_notice case final notice?) Text(notice),
              Expanded(
                child: m.events.isEmpty && !m.loading
                    ? EmptyState(title: l.activityTitle, body: l.activityEmpty)
                    : ListView.builder(
                        itemCount: m.events.length,
                        itemBuilder: (context, i) {
                          final e = m.events[i];
                          final ts = DateTime.parse(e.ts).toLocal();
                          return ListTile(
                            dense: true,
                            title: Text(describeEvent(l, e, nameOf)),
                            subtitle: Text(
                              [
                                '${dates.formatShortDate(ts)} ${dates.formatTimeOfDay(TimeOfDay.fromDateTime(ts))}',
                                if (e.actorUser case final actor?)
                                  nameOf(actor),
                              ].join(' · '),
                              style: muted,
                            ),
                            trailing: e.ipAddress == null
                                ? null
                                : Text(e.ipAddress!, style: muted),
                          );
                        },
                      ),
              ),
              if (m.hasMore)
                Align(
                  child: TextButton(
                    key: const Key('activity-more'),
                    onPressed: m.loading ? null : m.more,
                    child: Text(l.activityMore),
                  ),
                ),
              Text(l.activitySshNote, style: muted),
            ],
          );
        },
      ),
    );
  }
}
