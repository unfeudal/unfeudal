// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../../l10n/app_localizations.dart';
import '../../design/dialog.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';

/// The only place a member pin is made: true = the codes were compared, false = confirmed without comparing,
/// null = the codes differ or the dialog was closed.
Future<bool?> showSafetyCode(
  BuildContext context, {
  required String email,
  required List<int> publicKey,
}) => showUfDialog<bool>(
  context,
  (_) => SafetyCodeDialog(email: email, publicKey: publicKey),
);

class SafetyCodeDialog extends StatefulWidget {
  const SafetyCodeDialog({
    super.key,
    required this.email,
    required this.publicKey,
  });

  final String email;
  final List<int> publicKey;

  @override
  State<SafetyCodeDialog> createState() => _SafetyCodeDialogState();
}

class _SafetyCodeDialogState extends State<SafetyCodeDialog> {
  bool _compared = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    return UfDialog(
      title: l.safetyTitle(widget.email),
      message: l.safetyHint(widget.email),
      actions: [
        TextButton(
          key: const Key('safety-no-match'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.safetyNoMatch),
        ),
        FilledButton(
          key: const Key('safety-match'),
          onPressed: () => Navigator.of(context).pop(_compared),
          child: Text(l.safetyConfirm),
        ),
      ],
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.field,
            borderRadius: const BorderRadius.all(Radius.circular(10)),
          ),
          child: Text(
            safetyCode(widget.publicKey),
            textAlign: TextAlign.center,
            style: monoStyle.copyWith(fontSize: 18, letterSpacing: 1),
          ),
        ),
        CheckboxListTile(
          key: const Key('safety-compared'),
          value: _compared,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => setState(() => _compared = v ?? false),
          title: Text(l.safetyCompared),
        ),
      ],
    );
  }
}
