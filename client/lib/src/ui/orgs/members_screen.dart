// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/banner.dart';
import '../../design/buttons.dart';
import '../../design/choices.dart';
import '../../design/dialog.dart';
import '../../design/feedback.dart';
import '../../design/icons.dart';
import '../../design/rows.dart';
import '../../design/tokens.dart';
import '../../orgs/member_pins.dart';
import '../busy_action.dart';
import 'safety_code_dialog.dart';

String roleLabel(AppLocalizations l, OrgRole role) => switch (role) {
  OrgRole.owner => l.roleOwner,
  OrgRole.admin => l.roleAdmin,
  OrgRole.member => l.roleMember,
};

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
  await state.api!.orgs.removeMember(orgId, state.stored!.userId);
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

class _MembersScreenState extends State<MembersScreen> with BusyAction {
  // Pinned first, then confirmed on the server.
  Future<void> _confirm(OrgMember m) async {
    final verified = await showSafetyCode(
      context,
      email: m.email,
      publicKey: m.publicKey!,
    );
    if (verified == null) return;
    await run(() async {
      final state = AppScope.read(context);
      await state.orgs!.pins.pin(m.userId, m.publicKey!, verified: verified);
      await state.api!.orgs.confirmMember(widget.orgId, m.userId);
      await state.sync!.syncNow();
    });
  }

  // Pins a confirmed member on this device; a changed key rotates every folder they can view.
  Future<void> _verify(OrgMember m) async {
    final verified = await showSafetyCode(
      context,
      email: m.email,
      publicKey: m.publicKey!,
    );
    if (verified == null) return;
    await run(
      () => AppScope.read(context).orgs!.verifyMember(m, verified: verified),
    );
  }

  Future<void> _remove(OrgMember m) async {
    final l = AppLocalizations.of(context);
    final yes = await confirmDanger(
      context,
      question: l.memberRemoveConfirm(m.email),
      action: l.memberRemove,
    );
    if (!yes) return;
    await run(() async {
      final state = AppScope.read(context);
      await state.api!.orgs.removeMember(widget.orgId, m.userId);
      await state.sync!.syncNow();
    });
  }

  // Pins live in the vault: its changes redraw the badges.
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
          m.knownRole == OrgRole.owner &&
          m.status != MemberStatus.accepted.name &&
          m.disabled != true,
    );
    // a Material of its own: the section, a dialog or a test may host it
    return Material(
      type: MaterialType.transparency,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (problem case final error?)
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
    final role = m.knownRole;
    final accepted = m.status == MemberStatus.accepted.name;
    final self = m.userId == me;
    final touchable = isOwner || role?.isOwnerManaged == false;
    return ItemRow(
      icon: UfIcons.user,
      title: m.email,
      trailing: [
        if (isAdmin && accepted)
          UfStatusChip(l.memberAwaiting, tone: UfChipTone.warn),
        if (isAdmin && !self) ?_keyBadge(l, m, unconfirmed),
        if (isAdmin && role != null)
          _roleSelect(
            l,
            m,
            role,
            isOwner: isOwner,
            canChange: touchable && (!self || (isOwner && anotherOwner)),
          )
        else if (role != null)
          UfTag(roleLabel(l, role)),
        if (isAdmin && accepted && m.publicKey != null)
          FilledButton(
            key: Key('member-confirm-${m.userId}'),
            style: smallButton,
            onPressed: () => _confirm(m),
            child: Text(l.memberConfirm),
          ),
        if (isAdmin && !self && !accepted && _offersVerify(m))
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
    );
  }

  bool _keyChanged(OrgMember m) {
    final orgs = AppScope.read(context).orgs!;
    final key = m.publicKey;
    return (key != null &&
            orgs.pins.check(m.userId, key) == PinCheck.changed) ||
        orgs.alerts.contains(m.userId);
  }

  bool _offersVerify(OrgMember m) {
    final pin = AppScope.read(context).orgs!.pins.pinOf(m.userId);
    return m.publicKey != null &&
        (pin == null || !pin.verified || _keyChanged(m));
  }

  // The key badge an admin sees on another member.
  Widget? _keyBadge(AppLocalizations l, OrgMember m, Set<String> unconfirmed) {
    final pin = AppScope.read(context).orgs!.pins.pinOf(m.userId);
    final unpinned =
        m.status != MemberStatus.accepted.name &&
        pin == null &&
        (m.status != null || unconfirmed.contains(m.userId));
    if (_keyChanged(m)) {
      return UfStatusChip(
        l.memberKeyChanged,
        key: Key('member-key-changed-${m.userId}'),
        tone: UfChipTone.danger,
      );
    }
    if (pin != null) {
      return UfStatusChip(
        pin.verified ? l.memberVerified : l.memberNotVerified,
        tone: pin.verified ? UfChipTone.ok : UfChipTone.muted,
      );
    }
    if (unpinned) return UfStatusChip(l.memberUnpinned, tone: UfChipTone.muted);
    return null;
  }

  Widget _roleSelect(
    AppLocalizations l,
    OrgMember m,
    OrgRole role, {
    required bool isOwner,
    required bool canChange,
  }) {
    return UfSelect<OrgRole>(
      key: Key('member-role-${m.userId}'),
      value: role,
      onChanged: canChange
          ? (r) {
              if (r == role) return;
              unawaited(_setRole(m, r));
            }
          : null,
      options: [
        for (final r in OrgRole.values)
          UfOption(
            r,
            roleLabel(l, r),
            key: Key('role-option-${r.name}'),
            enabled: isOwner || !r.isOwnerManaged,
          ),
      ],
    );
  }

  Future<void> _setRole(OrgMember m, OrgRole role) => run(() async {
    final state = AppScope.read(context);
    await state.api!.orgs.setMemberRole(widget.orgId, m.userId, role);
    await state.sync!.syncNow();
  });
}
