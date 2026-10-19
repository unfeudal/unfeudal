// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../design/dialog.dart';
import '../../design/motion.dart';

/// Multi-line text for a terminal without bracketed paste: only the send button says yes.
Future<bool> confirmUnsafeMultiline(BuildContext context) async {
  final l = AppLocalizations.of(context);
  return await showUfDialog<bool>(
        context,
        alert: true,
        (dialog) => UfDialog(
          width: 480,
          title: l.multilineTitle,
          message: l.multilineBody,
          actions: [
            CancelButton(
              key: const Key('multiline-cancel'),
              onPressed: () => Navigator.pop(dialog, false),
            ),
            FilledButton(
              key: const Key('multiline-send'),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(l.multilineSend),
            ),
          ],
        ),
      ) ??
      false;
}
