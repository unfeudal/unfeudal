// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../design/seal.dart';
import '../../design/tokens.dart';
import '../../ssh/ssh_connector.dart';

/// First sight of a host key: the fingerprint, trust or cancel.
class HostKeyUnknownDialog extends StatelessWidget {
  const HostKeyUnknownDialog({super.key, required this.check});

  final HostKeyCheck check;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.hostKeyUnknownTitle),
      content: SelectionArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(l.hostKeyUnknownBody(check.hostName)),
            Text(check.keyType, style: monoStyle),
            Text(check.fingerprint, style: monoStyle),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('hostkey-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('hostkey-trust'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.hostKeyTrust),
        ),
      ],
    );
  }
}

/// A host key that differs from the pinned one: accepted only once the exact host name is typed.
class HostKeyChangedDialog extends StatefulWidget {
  const HostKeyChangedDialog({super.key, required this.check});

  final HostKeyCheck check;

  @override
  State<HostKeyChangedDialog> createState() => _HostKeyChangedDialogState();
}

class _HostKeyChangedDialogState extends State<HostKeyChangedDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final check = widget.check;
    final matches = _typed.text == check.hostName; // case-sensitive on purpose
    return AlertDialog(
      icon: const Seal(state: SealState.changed, size: 28),
      title: Text(l.hostKeyChangedTitle),
      content: SelectionArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(l.hostKeyChangedBody(check.hostName)),
            Text(
              l.hostKeyRecorded,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Text(check.pinned?.sha256Fingerprint ?? '', style: monoStyle),
            Text(
              l.hostKeyPresented,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Text(
              check.fingerprint,
              style: monoStyle.copyWith(color: UfColors.of(context).danger),
            ),
            TextField(
              key: const Key('hostkey-confirm-input'),
              controller: _typed,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l.hostKeyTypeName(check.hostName),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('hostkey-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('hostkey-accept'),
          style: FilledButton.styleFrom(
            backgroundColor: UfColors.of(context).danger,
          ),
          onPressed: matches ? () => Navigator.pop(context, true) : null,
          child: Text(l.hostKeyAccept),
        ),
      ],
    );
  }
}
