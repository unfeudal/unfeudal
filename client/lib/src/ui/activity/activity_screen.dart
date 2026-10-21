// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../audit/activity_model.dart';
import '../../audit/audit_anchors.dart';
import '../../debug_trace.dart';
import '../../design/banner.dart';
import '../../design/buttons.dart';
import '../../design/choices.dart';
import '../../design/empty_state.dart';
import '../../design/feedback.dart';
import '../../design/tokens.dart';
import '../describe_error.dart';
import '../hosts/editor_frame.dart';
import '../manage_frame.dart';
import '../save_file.dart';

part 'event_list.dart';

/// The audit views this account may read: in a vault, its actions and the org chain it administers or the
/// folders it manages; from Settings, its account chain or the instance. Verify and export read the whole chain.
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
    final model = ActivityModel(
      api: state.api!,
      anchors: AuditAnchors(state.mirror!),
      userId: state.stored!.userId,
      scope: scope,
    );
    unawaited(model.load());
    return model;
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

  bool get _fromSettings =>
      widget.scope == 'user' || widget.scope == 'instance';

  // The selected org's chain for its admins, else the account's own actions.
  String _initialScope() {
    if (widget.scope != 'me') return widget.scope;
    final orgs = AppScope.read(context).orgs;
    final orgId = orgs?.selected;
    return orgId != null && orgs!.isAdmin(orgId) ? 'org:$orgId' : 'me';
  }

  // The account and server chains in Settings; in a vault, the account's own actions and the selected
  // org's chain or the folders this account manages.
  List<(String, String)> _scopes(AppLocalizations l, AppState state) {
    final block = state.orgs?.block;
    return [
      if (_fromSettings) ...[
        if (widget.scope == 'user') ...[
          ('me', l.activityScopeMe),
          ('user', l.activityScopeAccount),
        ],
        if (widget.scope == 'instance') ('instance', l.activityScopeInstance),
      ] else
        for (final scope in ActivityModel.vaultScopes(state.orgs))
          (scope, _vaultScopeLabel(l, state, scope)),
      // a deleted org's chain, opened from its org.deleted event: the Instance Owner only
      if (_scope.startsWith('org:') &&
          !(block?.orgs.any((o) => 'org:${o.id}' == _scope) ?? false))
        (_scope, l.activityScopeDeletedOrg(shortId(_scope.substring(4)))),
    ];
  }

  String _vaultScopeLabel(AppLocalizations l, AppState state, String scope) =>
      switch (scope) {
        _ when scope.startsWith('org:') =>
          state.orgs!.byId(scope.substring(4))!.name,
        _ when scope.startsWith('folder:') => l.activityScopeFolder(
          state.vault?.entry(scope.substring(7))?.name ??
              shortId(scope.substring(7)),
        ),
        _ => l.activityScopeMe,
      };

  /// Ids only travel: items, members and orgs are named from what this device holds.
  String Function(String) _resolver(AppLocalizations l, AppState state) {
    final block = state.orgs?.block;
    return (id) {
      if (id == 'root') return l.activityRoot;
      final port = forwardPortOf(id);
      if (port != null) return port;
      if (id == state.stored!.userId) return l.activityYou;
      return state.vault?.entry(id)?.name ??
          block?.members.where((m) => m.userId == id).firstOrNull?.email ??
          state.orgs?.byId(id)?.name ??
          shortId(id);
    };
  }

  Future<void> _verify() async {
    final l = AppLocalizations.of(context);
    try {
      final chain = await _model.loadWholeChain();
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
    final muted = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: colors.muted);
    return ManageFrame(
      title: l.activityTitle,
      subtitle: _fromSettings
          ? null
          : vaultNameOf(l, state, state.orgs?.selected),
      onBack: widget.onBack,
      maxWidth: 980,
      child: ListenableBuilder(
        listenable: _model,
        builder: (context, _) {
          final m = _model;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              _ActivityToolbar(
                scopes: scopes,
                scope: _scope,
                hasChain: chain != null,
                onSelect: _select,
                onVerify: _verify,
                onExport: _export,
              ),
              if (m.alerts.firstOrNull case final alert?)
                _AnchorAlertNotice(alert: alert),
              if (m.error case final Exception e)
                UfNotice(tone: BannerTone.warn, message: describeError(l, e)),
              if (_notice case final notice?) Text(notice, style: muted),
              Expanded(
                child: m.events.isEmpty && !m.loading
                    ? EmptyState(title: l.activityTitle, body: l.activityEmpty)
                    : _EventList(
                        events: m.events,
                        nameOf: nameOf,
                        canOpenDeletedOrgs: state.stored!.isInstanceOwner,
                        onOpenOrg: (id) => _select('org:$id'),
                      ),
              ),
              if (m.hasMore) _LoadMoreButton(model: m),
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

class _AnchorAlertNotice extends StatelessWidget {
  const _AnchorAlertNotice({required this.alert});

  final AnchorAlert alert;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return UfNotice(
      key: const Key('activity-alert'),
      tone: BannerTone.danger,
      message: alert.kind == AnchorAlertKind.rewritten
          ? l.activityRewritten(alert.scope, alert.seq)
          : l.activityVanished(alert.scope, alert.seq),
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.model});

  final ActivityModel model;

  @override
  Widget build(BuildContext context) {
    return Align(
      child: TextButton(
        key: const Key('activity-more'),
        onPressed: model.loading ? null : model.loadMore,
        child: BusyLabel(
          busy: model.loading,
          label: AppLocalizations.of(context).activityMore,
        ),
      ),
    );
  }
}

class _ActivityToolbar extends StatelessWidget {
  const _ActivityToolbar({
    required this.scopes,
    required this.scope,
    required this.hasChain,
    required this.onSelect,
    required this.onVerify,
    required this.onExport,
  });

  final List<(String, String)> scopes;
  final String scope;
  final bool hasChain;
  final ValueChanged<String> onSelect;
  final VoidCallback onVerify;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      spacing: 8,
      children: [
        if (scopes.length > 1)
          UfSelect<String?>(
            key: const Key('activity-scope'),
            value: scopes.any((s) => s.$1 == scope) ? scope : null,
            options: [
              for (final (scope, label) in scopes)
                UfOption(scope, label, key: Key('activity-scope-$scope')),
            ],
            onChanged: (s) {
              if (s != null && s != scope) onSelect(s);
            },
          )
        else
          Text(
            scopes.first.$2,
            key: Key('activity-scope-${scopes.first.$1}'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        const Spacer(),
        if (hasChain) ...[
          OutlinedButton(
            key: const Key('activity-verify'),
            style: smallButton,
            onPressed: onVerify,
            child: Text(l.activityVerify),
          ),
          OutlinedButton(
            key: const Key('activity-export'),
            style: smallButton,
            onPressed: onExport,
            child: Text(l.activityExport),
          ),
        ],
      ],
    );
  }
}
