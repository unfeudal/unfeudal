// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/choices.dart';
import '../../design/tokens.dart';
import '../manage_frame.dart';
import 'acl_editor.dart';
import 'members_screen.dart';

/// What an org folder's access buttons open: its access editor (null without `manage`), and why this account
/// holds its rights there.
({VoidCallback? access, VoidCallback why}) orgFolderAccessActions(
  BuildContext context,
  String orgId,
  String folderId,
) {
  final state = AppScope.read(context);
  void push(Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));
  final manage = state.orgs!
      .permissions(orgId, folderId)
      .contains(Permission.manage);
  return (
    access: manage
        ? () => push(AclEditor(orgId: orgId, folderId: folderId))
        : null,
    why: () => push(
      WhyRightsView(
        orgId: orgId,
        folderId: folderId,
        userId: state.stored!.userId,
      ),
    ),
  );
}

/// The steps of the resolution for one member on one folder; admins pick any member.
class WhyRightsView extends StatefulWidget {
  const WhyRightsView({
    super.key,
    required this.orgId,
    required this.folderId,
    required this.userId,
  });

  final String orgId;
  final String folderId;
  final String userId;

  @override
  State<WhyRightsView> createState() => _WhyRightsViewState();
}

class _WhyRightsViewState extends State<WhyRightsView> {
  late String _userId = widget.userId;

  String? _describe(
    AppLocalizations l,
    ExplanationStep s, {
    required List<OrgMember> members,
    required String? role,
  }) {
    final state = AppScope.read(context);
    String principal(ExplanationStep s) => switch (s.principalType) {
      PrincipalType.team =>
        state.orgs!.block?.teams
                .where((t) => t.id == s.principalId)
                .firstOrNull
                ?.name ??
            '',
      _ =>
        members.where((m) => m.userId == s.principalId).firstOrNull?.email ??
            '',
    };
    String folder(String? id) => state.vault?.entry(id ?? '')?.name ?? '';
    return switch (s.kind) {
      StepKind.role => l.whyRole(
        roleLabel(
          l,
          OrgRole.values.firstWhere(
            (r) => r.name == role,
            orElse: () => OrgRole.admin,
          ),
        ),
      ),
      StepKind.entry => l.whyEntry(
        principal(s),
        folder(s.folderId),
        permissionList(l, s.permissions),
      ),
      StepKind.denied => l.whyDenied(permissionList(l, s.permissions)),
      StepKind.notConfirmed || StepKind.disabled => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final state = AppScope.of(context);
    final orgs = state.orgs!;
    final members = orgs.membersOf(widget.orgId);
    final why = orgs.explain(widget.orgId, widget.folderId, _userId);
    final role = members.where((m) => m.userId == _userId).firstOrNull?.role;
    final lines = [
      for (final s in why.steps) _describe(l, s, members: members, role: role),
    ].nonNulls;
    return ManageFrame(
      title: l.whyTitle,
      child: ListView(
        children: [
          if (orgs.isAdmin(widget.orgId))
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 320,
                child: UfSelect<String>(
                  key: const Key('why-member'),
                  value: _userId,
                  options: [
                    for (final m in members) UfOption(m.userId, m.email),
                  ],
                  onChanged: (id) => setState(() => _userId = id),
                ),
              ),
            ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(line),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              why.effective.isEmpty
                  ? l.whyNone
                  : l.whyResult(permissionList(l, why.effective)),
              style: TextStyle(color: colors.accentText),
            ),
          ),
        ],
      ),
    );
  }
}
