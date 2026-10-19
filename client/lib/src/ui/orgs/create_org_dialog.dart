// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../app_scope.dart';
import '../../design/dialog.dart';
import '../../design/tokens.dart';
import '../busy_action.dart';

/// Creates an org with the caller as owner, then shows it.
class CreateOrgDialog extends StatefulWidget {
  const CreateOrgDialog({super.key});

  @override
  State<CreateOrgDialog> createState() => _CreateOrgDialogState();
}

class _CreateOrgDialogState extends State<CreateOrgDialog> with BusyAction {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l = AppLocalizations.of(context);
    final state = AppScope.read(context);
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => problem = l.fieldRequired);
    await run(() async {
      final org = await state.api!.createOrg(name);
      await state.sync!.syncNow();
      state.orgs!.select(org.id);
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return UfDialog(
      title: l.railNewOrg,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('org-create'),
          onPressed: busy ? null : _create,
          child: Text(l.orgCreate),
        ),
      ],
      children: [
        TextField(
          key: const Key('org-name'),
          controller: _name,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(labelText: l.orgName),
          onSubmitted: (_) => _create(),
        ),
        if (problem case final error?)
          Text(error, style: TextStyle(color: UfColors.of(context).danger)),
      ],
    );
  }
}
