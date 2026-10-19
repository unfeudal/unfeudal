// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../l10n/app_localizations.dart';
import '../api/api_client.dart';
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
  bool hasMore = false;
  bool loading = false;
  Object? error;
  String? _next;

  /// The chain a view reads: `me` reads the caller's own chain; a folder view has no chain of its own.
  static String? chainOf(String scope) => switch (scope) {
    'me' => 'user',
    _ when scope.startsWith('folder:') => null,
    _ => scope,
  };

  static String exportFileName(String chainScope) =>
      'unfeudal-audit-${chainScope.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-')}.json';

  Future<void> load() {
    events.clear();
    _next = null;
    return _page();
  }

  Future<void> more() => _page();

  Future<void> _page() => _guard(() async {
    final page = await api.audit(scope: scope, after: _next);
    events.addAll(page.events);
    alerts.addAll(anchors.check(page.events));
    _next = page.next;
    hasMore = page.next != null;
  });

  /// Pages the whole chain at 500 a read and checks it against the anchors, an empty one too
  /// (a chain wiped after this device saw it is a rollback).
  Future<List<AuditEvent>> wholeChain() async {
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
      anchors.check(
        all,
        completeScope: chain == 'user' ? 'user:$userId' : chain,
      ),
    );
    notifyListeners();
    return all;
  }

  /// The first seq that does not verify, null when the chain holds.
  Future<int?> verify() async => verifyChain(await wholeChain());

  /// The whole chain as JSON, verified on the way: a broken chain is still saved (it is the evidence).
  Future<({String json, int? brokenAt})> exportJson() async {
    final chain = await wholeChain();
    return (
      json: jsonEncode([for (final e in chain) e.toJson()]),
      brokenAt: verifyChain(chain),
    );
  }

  /// Errors land in [error], never thrown to the UI.
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
  final t = at(0), x = at(1);
  return switch (e.action) {
    'setup.completed' => l.actSetupCompleted,
    'account.deleted' => l.actAccountDeleted(t),
    'org.created' => l.actOrgCreated,
    'org.updated' => l.actOrgUpdated,
    'org.deleted' => l.actOrgDeleted(t),
    'invite.created' => l.actInviteCreated,
    'invite.revoked' => l.actInviteRevoked,
    'invite.accepted' => l.actInviteAccepted(x),
    'admin.user_disabled' => l.actAdminUserDisabled(t),
    'admin.user_enabled' => l.actAdminUserEnabled(t),
    'audit.checkpoint' => l.actAuditCheckpoint(
      e.targetIds.firstOrNull?.replaceFirst('seq:', '') ?? '',
    ),
    'device.added' => l.actDeviceAdded,
    'device.revoked' => l.actDeviceRevoked,
    'auth.login_failed' => l.actAuthLoginFailed,
    'auth.refresh_replay' => l.actAuthRefreshReplay,
    'account.password_changed' => l.actAccountPasswordChanged,
    'account.recovery_used' => l.actAccountRecoveryUsed,
    'account.recovery_kit_changed' => l.actAccountRecoveryKitChanged,
    'item.created' => l.actItemCreated(t),
    'item.updated' => l.actItemUpdated(t),
    'item.deleted' => l.actItemDeleted(t),
    'item.restored' => l.actItemRestored(t),
    'item.purged' => l.actItemPurged(t),
    'item.moved' => l.actItemMoved(t, at(2)),
    'item.revealed' => l.actItemRevealed(t),
    'ssh.session_opened' => l.actSshSessionOpened(t),
    'ssh.session_closed' => l.actSshSessionClosed(t),
    'ssh.forward_started' => l.actSshForwardStarted(t, x),
    'ssh.forward_stopped' => l.actSshForwardStopped(t, x),
    'member.role_changed' => l.actMemberRoleChanged(t),
    'member.confirmed' => l.actMemberConfirmed(t),
    'member.removed' => l.actMemberRemoved(t),
    'team.created' => l.actTeamCreated(t),
    'team.updated' => l.actTeamUpdated(t),
    'team.deleted' => l.actTeamDeleted(t),
    'acl.changed' => l.actAclChanged(t),
    'folder.keys_rotated' => l.actFolderKeysRotated(t),
    'folder.keys_shared' => l.actFolderKeysShared(t),
    'folder.rotation_done' => l.actFolderRotationDone(t),
    _ => e.action,
  };
}
