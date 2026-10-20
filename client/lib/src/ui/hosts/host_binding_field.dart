// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../orgs/host_binding.dart';
import '../../vault/vault.dart';
import 'editor_frame.dart';

/// The caller's own key for a `perMember` org host, chosen among personal identities.
class HostBindingField extends StatelessWidget {
  const HostBindingField({super.key, required this.hostId});
  final String hostId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final vault = AppScope.of(context).vault!;
    return entryPicker(
      key: 'binding-identity',
      label: l.hostBindingLabel,
      none: l.hostDefault,
      entries: [
        for (final e in vault.ofKind(ItemKind.identity))
          if (e.state == EntryState.ok && e.orgId == null) e,
      ],
      value: bindingFor(vault, hostId),
      onChanged: (id) {
        if (id != null) unawaited(bindHost(vault, hostId, id));
      },
    );
  }
}
