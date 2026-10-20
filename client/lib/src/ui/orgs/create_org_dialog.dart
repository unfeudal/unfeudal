// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../form_dialog.dart';

/// Creates an org with the caller as owner, then shows it.
class CreateOrgDialog extends StatelessWidget {
  const CreateOrgDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    return FormDialog(
      title: l.railNewOrg,
      fields: [
        FormDialogField(
          'org-name',
          l.orgName,
          autofocus: true,
          maxLength: 100,
          isRequired: true,
          submitOnEnter: true,
        ),
      ],
      saveKey: 'org-create',
      saveLabel: l.orgCreate,
      onSave: (values) async {
        final org = await state.api!.orgs.create(values['org-name']!.trim());
        await state.sync!.syncNow();
        state.orgs!.select(org.id);
      },
    );
  }
}
