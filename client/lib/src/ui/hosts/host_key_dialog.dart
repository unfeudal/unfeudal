// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../design/dialog.dart';
import '../../design/field.dart';
import '../../design/logo.dart';
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
    final colors = UfColors.of(context);
    return UfDialog(
      // Loquet's place
      leading: UfLogo(size: 56, color: colors.muted),
      title: l.hostKeyUnknownTitle,
      message: l.hostKeyUnknownBody(check.hostName),
      actions: [
        CancelButton(
          key: const Key('hostkey-cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          key: const Key('hostkey-trust'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.hostKeyTrust),
        ),
      ],
      children: [
        _FingerprintBox(
          fill: colors.field,
          leading: const Seal(state: SealState.verify, size: 16),
          lines: [check.keyType, check.fingerprint],
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
    final colors = UfColors.of(context);
    final check = widget.check;
    final matches = _typed.text == check.hostName; // case-sensitive on purpose
    return UfDialog(
      width: 600,
      leading: const Seal(state: SealState.changed, size: 32),
      title: l.hostKeyChangedTitle,
      message: l.hostKeyChangedBody(check.hostName),
      actions: [
        TextButton(
          key: const Key('hostkey-accept'),
          style: TextButton.styleFrom(foregroundColor: colors.dangerText),
          onPressed: matches ? () => Navigator.pop(context, true) : null,
          child: Text(l.hostKeyAccept),
        ),
        FilledButton(
          key: const Key('hostkey-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
      ],
      children: [
        _FingerprintBox(
          fill: colors.field,
          label: l.hostKeyRecorded,
          lines: [check.pinned?.sha256Fingerprint ?? ''],
        ),
        _FingerprintBox(
          fill: colors.dangerSoft,
          label: l.hostKeyPresented,
          labelColor: colors.dangerText,
          lines: [check.fingerprint],
        ),
        UfField(
          label: l.hostKeyTypeName(check.hostName),
          child: TextField(
            key: const Key('hostkey-confirm-input'),
            controller: _typed,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: check.hostName),
          ),
        ),
      ],
    );
  }
}

/// A filled box of selectable mono lines, with an optional label or seal.
class _FingerprintBox extends StatelessWidget {
  const _FingerprintBox({
    required this.fill,
    required this.lines,
    this.label,
    this.labelColor,
    this.leading,
  });

  final Color fill;
  final List<String> lines;
  final String? label;
  final Color? labelColor;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          ?leading,
          Expanded(
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  if (label case final label?)
                    Text(
                      label,
                      style: TextStyle(
                        color: labelColor ?? colors.muted,
                        fontSize: 13,
                        fontWeight: labelColor == null
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                  for (final line in lines)
                    Text(line, style: monoStyle.copyWith(fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
