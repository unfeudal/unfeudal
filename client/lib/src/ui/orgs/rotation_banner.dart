// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../app_state.dart';
import '../../design/banner.dart';
import '../../design/buttons.dart';
import '../../design/feedback.dart';
import '../../design/tokens.dart';

/// Folder keys to change in the orgs the caller administers, readers to confirm first, refused keys: full-width
/// banners over the sessions, or [RotationBanner.row] notices at the top of a section.
class RotationBanner extends StatelessWidget {
  const RotationBanner({super.key}) : _row = false;

  const RotationBanner.row({super.key}) : _row = true;

  final bool _row;

  static List<PendingRotation> _pending(AppState state) {
    final orgs = state.orgs;
    return [
      for (final p
          in orgs?.block?.pendingRotations ?? const <PendingRotation>[])
        if (orgs!.isAdmin(p.orgId)) p,
    ];
  }

  /// Whether the banner has anything to say.
  static bool shows(AppState state) =>
      _pending(state).isNotEmpty || (state.orgs?.alerts.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    final state = AppScope.of(context);
    final orgs = state.orgs;
    if (orgs == null || !shows(state)) return const SizedBox.shrink();
    final pending = _pending(state);
    final blocked = orgs.lastRotation?.blocked ?? const <String>{};
    final emails = [
      for (final m in orgs.block?.members ?? const <OrgMember>[])
        if (blocked.contains(m.userId)) m.email,
    ];
    final note = TextStyle(color: colors.muted, fontSize: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        if (pending.isNotEmpty) ...[
          if (_row)
            UfNotice.row(
              tone: BannerTone.warn,
              message: l.rotationPending(pending.length),
              actions: [
                OutlinedButton(
                  key: const Key('rotation-now'),
                  style: smallButton,
                  onPressed: () => unawaited(orgs.rotateNow()),
                  child: Text(l.rotationNow),
                ),
              ],
            )
          else
            StatusBanner(
              tone: BannerTone.warn,
              message: l.rotationPending(pending.length),
              action: (l.rotationNow, () => unawaited(orgs.rotateNow())),
              actionKey: const Key('rotation-now'),
            ),
          Text(l.rotationCredentials, style: note),
          if (emails.isNotEmpty)
            Text(
              l.rotationBlocked(emails.length, emails.join(', ')),
              style: note,
            ),
        ],
        if (orgs.alerts.isNotEmpty)
          if (_row)
            UfNotice.row(
              tone: BannerTone.danger,
              message: l.keyAlert(orgs.alerts.length),
            )
          else
            StatusBanner(
              tone: BannerTone.danger,
              message: l.keyAlert(orgs.alerts.length),
            ),
      ],
    );
  }
}
