// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import 'icons.dart';
import 'tokens.dart';

enum UfToastTone { ok, info, warn }

/// Shows a notification: an 18 px icon in the [tone]'s colour and the message in 600; it leaves after 5 s.
void showUfToast(
  BuildContext context,
  String message, {
  UfToastTone tone = UfToastTone.ok,
}) {
  final colors = UfColors.of(context);
  final (icon, color) = switch (tone) {
    UfToastTone.ok => (UfIcons.checkCircle, colors.ok),
    UfToastTone.info => (UfIcons.info, colors.accentText),
    UfToastTone.warn => (UfIcons.warning, colors.warn),
  };
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 5),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: color),
          ),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium!
                  .copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}
