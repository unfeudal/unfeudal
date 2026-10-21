// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../l10n/app_localizations.dart';
import '../api/api_client.dart';
import '../orgs/org_controller.dart';
import 'audit_anchors.dart';

/// One audit view, paged; verify and export always read the whole chain behind it, never the filtered view.
class ActivityModel extends ChangeNotifier {
  ActivityModel({
    required this.api,
    required this.anchors,
    required this.userId,
    required this.scope,
  });

  final ApiClient api;
  final AuditAnchors anchors;
  final String userId;
  final String scope;

  final events = <AuditEvent>[];
  final alerts = <AnchorAlert>[];
  bool loading = false;
  Object? error;
  String? _next;
  bool get hasMore => _next != null;

  /// The chain a view reads: `me` reads the caller's own chain; a folder view has no chain of its own.
  static String? chainOf(String scope) => switch (scope) {
    'me' => 'user',
    _ when scope.startsWith('folder:') => null,
    _ => scope,
  };

  /// The views a vault offers: the account's own actions, then the selected org's chain for its admins or the
  /// folders this account manages in it.
  static List<String> vaultScopes(OrgController? orgs) {
    final orgId = orgs?.selected;
    if (orgs == null || orgId == null || orgs.byId(orgId) == null) {
      return const ['me'];
    }
    return [
      'me',
      if (orgs.isAdmin(orgId))
        'org:$orgId'
      else
        for (final n in orgs.block!.folderTree)
          if (n.orgId == orgId &&
              orgs.permissions(orgId, n.folderId).contains(Permission.manage))
            'folder:${n.folderId}',
    ];
  }

  static String exportFileName(String chainScope) =>
      'unfeudal-audit-${chainScope.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-')}.json';

  Future<void> load() {
    events.clear();
    _next = null;
    return _page();
  }

  Future<void> loadMore() => _page();

  Future<void> _page() => _guard(() async {
    final page = await api.audit(scope: scope, after: _next);
    events.addAll(page.events);
    alerts.addAll(anchors.checkAndAdvance(page.events));
    _next = page.next;
  });

  /// Pages the whole chain at 500 a read and checks it against the anchors, an empty one too
  /// (a chain wiped after this device saw it is a rollback).
  Future<List<AuditEvent>> loadWholeChain() async {
    final chain = chainOf(scope);
    if (chain == null) return const [];
    final all = <AuditEvent>[];
    String? after;
    do {
      final page = await api.audit(scope: chain, after: after, limit: 500);
      all.addAll(page.events);
      after = page.next;
    } while (after != null);
    alerts.addAll(
      anchors.checkAndAdvance(
        all,
        completeScope: chain == 'user' ? 'user:$userId' : chain,
      ),
    );
    notifyListeners();
    return all;
  }

  /// The first seq that does not verify, null when the chain holds.
  Future<int?> verify() async => verifyChain(await loadWholeChain());

  /// The whole chain as JSON, verified on the way: a broken chain is still saved (it is the evidence).
  Future<({String json, int? brokenAt})> exportJson() async {
    final chain = await loadWholeChain();
    return (
      json: jsonEncode([for (final e in chain) e.toJson()]),
      brokenAt: verifyChain(chain),
    );
  }

  // Errors land in error, never thrown to the UI.
  Future<void> _guard(Future<void> Function() action) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } on ApiException catch (e) {
      error = e;
    } on NetworkException catch (e) {
      error = e;
    } on FormatException catch (e) {
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

/// The event as a sentence; names resolved locally (only ids travel). An unknown action shows as sent.
String describeEvent(
  AppLocalizations l,
  AuditEvent e,
  String Function(String id) nameOf,
) {
  String at(int i) => i < e.targetIds.length ? nameOf(e.targetIds[i]) : '';
  final first = at(0), second = at(1);
  return switch (e.action) {
    'setup.completed' => l.actSetupCompleted,
    'account.deleted' => l.actAccountDeleted(first),
    'org.created' => l.actOrgCreated,
    'org.updated' => l.actOrgUpdated,
    'org.deleted' => l.actOrgDeleted(first),
    'invite.created' => l.actInviteCreated,
    'invite.revoked' => l.actInviteRevoked,
    'invite.accepted' => l.actInviteAccepted(second),
    'admin.user_disabled' => l.actAdminUserDisabled(first),
    'admin.user_enabled' => l.actAdminUserEnabled(first),
    'audit.checkpoint' => l.actAuditCheckpoint('${checkpointOf(e)?.seq ?? ''}'),
    'device.added' => l.actDeviceAdded,
    'device.revoked' => l.actDeviceRevoked,
    'auth.login_failed' => l.actAuthLoginFailed,
    'auth.refresh_replay' => l.actAuthRefreshReplay,
    'account.password_changed' => l.actAccountPasswordChanged,
    'account.recovery_used' => l.actAccountRecoveryUsed,
    'account.recovery_kit_changed' => l.actAccountRecoveryKitChanged,
    'item.created' => l.actItemCreated(first),
    'item.updated' => l.actItemUpdated(first),
    'item.deleted' => l.actItemDeleted(first),
    'item.restored' => l.actItemRestored(first),
    'item.purged' => l.actItemPurged(first),
    'item.moved' => l.actItemMoved(first, at(2)),
    'item.revealed' => l.actItemRevealed(first),
    'ssh.session_opened' => l.actSshSessionOpened(first),
    'ssh.session_closed' => l.actSshSessionClosed(first),
    'ssh.forward_started' => l.actSshForwardStarted(first, second),
    'ssh.forward_stopped' => l.actSshForwardStopped(first, second),
    'member.role_changed' => l.actMemberRoleChanged(first),
    'member.confirmed' => l.actMemberConfirmed(first),
    'member.removed' => l.actMemberRemoved(first),
    'team.created' => l.actTeamCreated(first),
    'team.updated' => l.actTeamUpdated(first),
    'team.deleted' => l.actTeamDeleted(first),
    'acl.changed' => l.actAclChanged(first),
    'folder.keys_rotated' => l.actFolderKeysRotated(first),
    'folder.keys_shared' => l.actFolderKeysShared(first),
    'folder.rotation_done' => l.actFolderRotationDone(first),
    _ => e.action,
  };
}
