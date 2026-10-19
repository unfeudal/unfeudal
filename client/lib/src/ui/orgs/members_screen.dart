// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/banner.dart';
import '../../design/buttons.dart';
import '../../design/dialog.dart';
import '../../design/rows.dart';
import '../../design/tokens.dart';
import '../../orgs/member_pins.dart';
import '../describe_error.dart';
import 'safety_code_dialog.dart';

String roleLabel(AppLocalizations l, OrgRole role) => switch (role) {
  OrgRole.owner => l.roleOwner,
  OrgRole.admin => l.roleAdmin,
  OrgRole.member => l.roleMember,
};

OrgRole? _roleOf(String wire) =>
    OrgRole.values.where((r) => r.name == wire).firstOrNull;

/// Asks, then leaves [orgId]: allowed to any member, confirmed or not.
Future<void> confirmAndLeaveOrg(
  BuildContext context,
  String orgId,
  String orgName,
) async {
  final l = AppLocalizations.of(context);
  final state = AppScope.read(context);
  final yes = await confirmDanger(
    context,
    question: l.orgLeaveConfirm(orgName),
    action: l.orgLeave,
  );
  if (!yes) return;
  await state.api!.removeMember(orgId, state.stored!.userId);
  state.orgs!.select(null);
  await state.sync!.syncNow();
}

/// The org's members from the cached block: admins see status and keys, confirm and verify through the safety
/// code, change roles and remove.
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key, required this.orgId});

  final String orgId;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  String? _error;

  Future<void> _run(Future<void> Function(AppState state) action) async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    try {
      await action(state);
      if (mounted) setState(() => _error = null);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
    }
  }

  /// Confirms an accepted member: pinned first, then confirmed on the server.
  Future<void> _confirm(OrgMember m) async {
    final verified = await showSafetyCode(
      context,
      email: m.email,
      publicKey: m.publicKey!,
    );
    if (verified == null) return;
    await _run((state) async {
      await state.orgs!.pins.pin(m.userId, m.publicKey!, verified: verified);
      await state.api!.confirmMember(widget.orgId, m.userId);
      await state.sync!.syncNow();
    });
  }

  /// Pins a confirmed member on this device; a changed key rotates every folder they can view.
  Future<void> _verify(OrgMember m) async {
    final orgs = AppScope.read(context).orgs!;
    final changed = orgs.pins.check(m.userId, m.publicKey!) == PinCheck.changed;
    final verified = await showSafetyCode(
      context,
      email: m.email,
      publicKey: m.publicKey!,
    );
    if (verified == null) return;
    await _run((state) async {
      await orgs.pins.pin(m.userId, m.publicKey!, verified: verified);
      orgs.alerts.remove(m.userId);
      await state.sync!.syncNow();
      final block = orgs.block;
      if (!changed || block == null) return;
      for (final n in block.folderTree.where((n) => n.orgId == widget.orgId)) {
        final perms = orgs.permissions(
          widget.orgId,
          n.folderId,
          userId: m.userId,
        );
        if (perms.contains(Permission.view)) {
          await orgs.rotation.rotate(block, widget.orgId, n.folderId);
        }
      }
    });
  }

  Future<void> _remove(OrgMember m) async {
    final l = AppLocalizations.of(context);
    final yes = await confirmDanger(
      context,
      question: l.memberRemoveConfirm(m.email),
      action: l.memberRemove,
    );
    if (!yes) return;
    await _run((state) async {
      await state.api!.removeMember(widget.orgId, m.userId);
      await state.sync!.syncNow();
    });
  }

  /// Pins live in the vault: its changes redraw the badges.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppScope.of(context).vault!,
    builder: (context, _) => _members(context),
  );

  Widget _members(BuildContext context) {
    final state = AppScope.of(context);
    final orgs = state.orgs!;
    final me = state.stored!.userId;
    final isAdmin = orgs.isAdmin(widget.orgId);
    final isOwner = isAdmin && orgs.isOwner(widget.orgId);
    final members = orgs.membersOf(widget.orgId);
    final unconfirmed = orgs.lastHandoff?.unconfirmed ?? const <String>{};
    // an owner may change their own role while another confirmed owner remains
    final anotherOwner = members.any(
      (m) =>
          m.userId != me &&
          m.role == OrgRole.owner.name &&
          m.status != MemberStatus.accepted.name &&
          m.disabled != true,
    );
    // a Material of its own: the section, a dialog or a test may host it
    return Material(
      type: MaterialType.transparency,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (_error case final error?)
            StatusBanner(tone: BannerTone.danger, message: error),
          for (final m in members)
            _row(
              context,
              m,
              me: me,
              isAdmin: isAdmin,
              isOwner: isOwner,
              unconfirmed: unconfirmed,
              anotherOwner: anotherOwner,
            ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    OrgMember m, {
    required String me,
    required bool isAdmin,
    required bool isOwner,
    required Set<String> unconfirmed,
    required bool anotherOwner,
  }) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final orgs = AppScope.of(context).orgs!;
    final role = _roleOf(m.role);
    final accepted = m.status == MemberStatus.accepted.name;
    final self = m.userId == me;
    final key = m.publicKey;
    final pin = orgs.pins.pinOf(m.userId);
    final changed =
        (key != null && orgs.pins.check(m.userId, key) == PinCheck.changed) ||
        orgs.alerts.contains(m.userId);
    final unpinned =
        !accepted &&
        pin == null &&
        (m.status != null || unconfirmed.contains(m.userId));
    final muted = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: colors.muted);
    final badges = <Widget>[
      if (isAdmin && accepted)
        Text(l.memberAwaiting, style: muted.copyWith(color: colors.warn)),
      if (isAdmin && !self && changed)
        Text(
          l.memberKeyChanged,
          key: Key('member-key-changed-${m.userId}'),
          style: muted.copyWith(color: colors.danger),
        )
      else if (isAdmin && !self && pin != null)
        Text(
          pin.verified ? l.memberVerified : l.memberNotVerified,
          style: pin.verified ? muted.copyWith(color: colors.ok) : muted,
        )
      else if (isAdmin && !self && unpinned)
        Text(l.memberUnpinned, style: muted),
    ];
    final touchable = isOwner || role == OrgRole.member;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          spacing: 12,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.neutral,
                borderRadius: UfRadius.control,
              ),
              child: Text(
                m.email.isEmpty ? '?' : m.email[0].toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.email,
                    style: Theme.of(context).textTheme.labelLarge!
                        .copyWith(fontSize: 13.5),
                  ),
                  ...badges,
                ],
              ),
            ),
            if (isAdmin && role != null)
              DropdownButton<OrgRole>(
                key: Key('member-role-${m.userId}'),
                value: role,
                underline: const SizedBox.shrink(),
                onChanged: touchable && (!self || (isOwner && anotherOwner))
                    ? (r) {
                        if (r == null || r == role) return;
                        _run((state) async {
                          await state.api!.setMemberRole(
                            widget.orgId,
                            m.userId,
                            r,
                          );
                          await state.sync!.syncNow();
                        });
                      }
                    : null,
                items: [
                  for (final r in OrgRole.values)
                    DropdownMenuItem(
                      key: Key('role-option-${r.name}'),
                      value: r,
                      enabled: isOwner || r == OrgRole.member,
                      child: Text(roleLabel(l, r)),
                    ),
                ],
              )
            else if (role != null)
              UfTag(roleLabel(l, role)),
            if (isAdmin && accepted && key != null)
              FilledButton(
                key: Key('member-confirm-${m.userId}'),
                style: smallButton,
                onPressed: () => _confirm(m),
                child: Text(l.memberConfirm),
              ),
            if (isAdmin &&
                !self &&
                !accepted &&
                key != null &&
                (pin == null || !pin.verified || changed))
              OutlinedButton(
                key: Key('member-verify-${m.userId}'),
                style: smallButton,
                onPressed: () => _verify(m),
                child: Text(l.memberVerify),
              ),
            if (isAdmin && !self && touchable)
              TextButton(
                key: Key('member-remove-${m.userId}'),
                style: dangerQuietStyle(colors).merge(smallButton),
                onPressed: () => _remove(m),
                child: Text(l.memberRemove),
              ),
          ],
        ),
      ),
    );
  }
}
