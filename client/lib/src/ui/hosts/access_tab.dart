// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/buttons.dart';
import '../../design/rows.dart';
import '../../design/tokens.dart';
import '../orgs/acl_editor.dart';
import '../orgs/why_rights_view.dart';

/// The inspector's Accès tab for an org item: who holds which rights on [folderId], then « Modifier les
/// accès » (with manage) and « Pourquoi ces droits ? ».
class AccessTab extends StatelessWidget {
  const AccessTab({super.key, required this.orgId, required this.folderId});

  final String orgId;
  final String folderId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.of(context);
    final colors = UfColors.of(context);
    final orgs = state.orgs!;
    final block = orgs.block;
    Set<Permission> perms(List<String> names) => {
      for (final n in names) ...Permission.values.where((p) => p.name == n),
    };
    String who(AclRow a) => a.principalType == 'team'
        ? block?.teams.where((t) => t.id == a.principalId).firstOrNull?.name ??
              ''
        : block?.members
                  .where((m) => m.userId == a.principalId)
                  .firstOrNull
                  ?.email ??
              '';
    final rows = [
      for (final a in block?.acl ?? const <AclRow>[])
        if (a.orgId == orgId && a.folderId == folderId) a,
    ];
    final (:access, :why) = orgFolderAccessActions(context, orgId, folderId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (rows.isEmpty)
          Text(
            l.accessNone,
            style: Theme.of(context).textTheme.bodySmall!
                .copyWith(color: colors.muted),
          ),
        for (final a in rows)
          ItemRow(
            key: Key('access-${a.principalId}'),
            title: who(a),
            subtitle: [
              if (a.allow.isNotEmpty) permissionList(l, perms(a.allow)),
              if (a.deny.isNotEmpty)
                l.accessDenied(permissionList(l, perms(a.deny))),
            ].join(' · '),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (access != null)
              OutlinedButton(
                key: const Key('access-edit'),
                style: smallButton,
                onPressed: access,
                child: Text(l.accessEdit),
              ),
            TextButton(
              key: const Key('access-why'),
              style: smallButton,
              onPressed: why,
              child: Text(l.whyTitle),
            ),
          ],
        ),
      ],
    );
  }
}
