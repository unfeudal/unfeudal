// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../design/dialog.dart';
import '../../design/seal.dart';
import '../../design/tokens.dart';
import '../../loquet/loquet_pose.dart';
import '../../loquet/loquet_spot.dart';
import '../../ssh/ssh_connector.dart';
import '../fields.dart';

/// First sight of a host key: the fingerprint, trust or cancel.
class HostKeyUnknownDialog extends StatelessWidget {
  const HostKeyUnknownDialog({super.key, required this.check});

  final HostKeyCheck check;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    return UfDialog(
      leading: const LoquetSpot(
        placement: LoquetPlacement.dialog,
        mood: LoquetMood.connecting,
      ),
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
          fill: colors.panel,
          edge: colors.line,
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
    // case-sensitive on purpose
    final matches = _typed.text == check.hostName;
    return UfDialog(
      width: 580,
      leading: const LoquetSpot(
        placement: LoquetPlacement.dialog,
        mood: LoquetMood.alert,
      ),
      title: l.hostKeyChangedTitle,
      message: l.hostKeyChangedBody(check.hostName),
      // the least risky answer takes the initial focus
      actions: [
        OutlinedButton(
          key: const Key('hostkey-cancel'),
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.hostKeyCancelConnection),
        ),
        FilledButton(
          key: const Key('hostkey-accept'),
          style: dangerButtonStyle(colors),
          onPressed: matches ? () => Navigator.pop(context, true) : null,
          child: Text(l.hostKeyAccept),
        ),
      ],
      children: [
        _FingerprintBox(
          fill: colors.panel,
          edge: colors.line,
          label: l.hostKeyRecorded,
          lines: [check.pinned?.sha256Fingerprint ?? ''],
        ),
        _FingerprintBox(
          fill: colors.dangerSoft,
          label: l.hostKeyPresented,
          labelColor: colors.danger,
          lines: [check.fingerprint],
        ),
        keyedField(
          'hostkey-confirm-input',
          _typed,
          l.hostKeyTypeName(check.hostName),
          mono: true,
          hint: check.hostName,
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}

// A filled box of selectable mono lines, with an optional label or seal.
class _FingerprintBox extends StatelessWidget {
  const _FingerprintBox({
    required this.fill,
    required this.lines,
    this.label,
    this.labelColor,
    this.leading,
    this.edge,
  });

  final Color fill;
  final List<String> lines;
  final String? label;
  final Color? labelColor;
  final Widget? leading;
  final Color? edge;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: UfRadius.control,
        border: edge == null ? null : Border.all(color: edge!),
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
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  for (final line in lines)
                    Text(line, style: monoStyle.copyWith(fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
