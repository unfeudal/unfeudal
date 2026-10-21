// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/toast.dart';
import '../../orgs/host_binding.dart';
import '../../vault/vault.dart';
import '../describe_error.dart';
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
      entries: vault.usableOfKind(ItemKind.identity, orgId: null),
      value: bindingFor(vault, hostId),
      onChanged: (id) async {
        if (id == null) return;
        try {
          await bindHost(vault, hostId, id);
        } on Exception catch (e) {
          if (context.mounted) {
            showUfToast(context, describeError(l, e), tone: UfToastTone.warn);
          }
        }
      },
    );
  }
}
