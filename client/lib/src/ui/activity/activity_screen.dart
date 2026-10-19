// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../audit/activity_model.dart';
import '../../audit/audit_anchors.dart';
import '../../design/banner.dart';
import '../../design/buttons.dart';
import '../../design/empty_state.dart';
import '../../design/tokens.dart';
import '../describe_error.dart';
import '../hosts/editor_frame.dart';
import '../manage_frame.dart';
import '../save_file.dart';

/// The audit views this account may read: in a vault, its actions and the org chain it administers or the
/// folders it manages; from Réglages, its account chain or the instance. Verify and export read the whole chain.
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
  late String _scope = _initialScope();
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

  /// Opened from Réglages on the account or server chain; otherwise the section of the selected vault.
  bool get _fromSettings =>
      widget.scope == 'user' || widget.scope == 'instance';

  /// The selected org's chain for its admins, else « Mes actions ».
  String _initialScope() {
    if (widget.scope != 'me') return widget.scope;
    final orgs = AppScope.read(context).orgs;
    final orgId = orgs?.selected;
    return orgId != null && orgs!.isAdmin(orgId) ? 'org:$orgId' : 'me';
  }

  /// (scope, label) pairs offered here: the account and server chains in Réglages; « Mes actions » and the
  /// selected org's chain or the folders this account manages in a vault.
  List<(String, String)> _scopes(AppLocalizations l, AppState state) {
    final block = state.orgs?.block;
    final orgId = state.orgs?.selected;
    return [
      if (_fromSettings) ...[
        if (widget.scope == 'user') ...[
          ('me', l.activityScopeMe),
          ('user', l.activityScopeAccount),
        ],
        if (widget.scope == 'instance') ('instance', l.activityScopeInstance),
      ] else ...[
        ('me', l.activityScopeMe),
        for (final org in block?.orgs ?? const <OrgSummary>[])
          if (org.id == orgId)
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
      ],
      // a deleted org's chain, opened from its org.deleted event: the Instance Owner only
      if (_scope.startsWith('org:') &&
          !(block?.orgs.any((o) => 'org:${o.id}' == _scope) ?? false))
        (_scope, l.activityScopeDeletedOrg(_scope.substring(4, 12))),
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
      final brokenAt = verifyChain(chain);
      final count = chain.length;
      if (!mounted) return;
      setState(
        () => _notice = brokenAt == null
            ? l.activityVerified(count)
            : l.activityBroken(brokenAt),
      );
    } on Exception catch (e) {
      if (mounted) setState(() => _notice = describeError(l, e));
    }
  }

  Future<void> _export() async {
    final l = AppLocalizations.of(context);
    final chain = ActivityModel.chainOf(_scope)!;
    try {
      final path = await (widget.savePath ?? pickSaveLocation)(
        ActivityModel.exportFileName(chain),
      );
      if (path == null) return;
      final out = await _model.exportJson();
      await (widget.writeFile ?? writeFileBytes)(path, utf8.encode(out.json));
      if (!mounted) return;
      final brokenAt = out.brokenAt;
      setState(
        () => _notice = brokenAt == null
            ? l.activityExported(path)
            : l.activityExportedBroken(path, brokenAt),
      );
    } on Exception catch (e) {
      if (mounted) setState(() => _notice = describeError(l, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final state = AppScope.of(context);
    final scopes = _scopes(l, state);
    final chain = ActivityModel.chainOf(_scope);
    final nameOf = _resolver(l, state);
    final dates = MaterialLocalizations.of(context);
    final muted = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: colors.muted);
    final orgId = state.orgs?.selected;
    final vaultName = vaultNameOf(l, state, orgId);
    return ManageFrame(
      title: l.activityTitle,
      subtitle: _fromSettings ? null : vaultName,
      onBack: widget.onBack,
      maxWidth: 980,
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
                  if (scopes.length > 1)
                    DropdownButton<String>(
                      key: const Key('activity-scope'),
                      value: scopes.any((s) => s.$1 == _scope) ? _scope : null,
                      underline: const SizedBox.shrink(),
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
                    )
                  else
                    Text(
                      scopes.first.$2,
                      key: Key('activity-scope-${scopes.first.$1}'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  const Spacer(),
                  if (chain != null) ...[
                    OutlinedButton(
                      key: const Key('activity-verify'),
                      style: smallButton,
                      onPressed: _verify,
                      child: Text(l.activityVerify),
                    ),
                    OutlinedButton(
                      key: const Key('activity-export'),
                      style: smallButton,
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
              if (_notice case final notice?) Text(notice, style: muted),
              Expanded(
                child: m.events.isEmpty && !m.loading
                    ? EmptyState(title: l.activityTitle, body: l.activityEmpty)
                    : ListView.builder(
                        itemCount: m.events.length,
                        itemBuilder: (context, i) {
                          final e = m.events[i];
                          final ts = DateTime.parse(e.ts).toLocal();
                          return EventRow(
                            when:
                                '${dates.formatShortDate(ts)} ${dates.formatTimeOfDay(TimeOfDay.fromDateTime(ts))}',
                            text: describeEvent(l, e, nameOf),
                            who: [
                              if (e.actorUser case final actor?) nameOf(actor),
                              ?e.ipAddress,
                            ].join(' · '),
                            trailing:
                                e.action == 'org.deleted' &&
                                    state.stored!.isInstanceOwner &&
                                    e.targetIds.isNotEmpty
                                ? OutlinedButton(
                                    key: Key(
                                      'activity-open-org-${e.targetIds.first}',
                                    ),
                                    style: smallButton,
                                    onPressed: () =>
                                        _select('org:${e.targetIds.first}'),
                                    child: Text(l.activityOpenDeletedOrg),
                                  )
                                : null,
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
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(l.activitySshNote, style: muted),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One audit event: when, what, who; the same row for every chain.
class EventRow extends StatelessWidget {
  const EventRow({
    super.key,
    required this.when,
    required this.text,
    required this.who,
    this.trailing,
  });

  final String when;
  final String text;
  final String who;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final muted = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: colors.muted);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          spacing: 16,
          children: [
            SizedBox(width: 130, child: Text(when, style: muted)),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(fontSize: 13.5),
              ),
            ),
            if (who.isNotEmpty) Text(who, style: muted),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
