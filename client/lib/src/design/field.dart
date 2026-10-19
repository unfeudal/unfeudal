// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import 'icons.dart';
import 'tokens.dart';

/// A label above its input, then an optional source line (an inherited value) and an error.
class UfField extends StatelessWidget {
  const UfField({
    super.key,
    required this.label,
    required this.child,
    this.source,
    this.error,
  });

  final String label;
  final Widget child;

  /// Where an empty field's value comes from, shown with the inheritance arrow.
  final String? source;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    final help = text.bodySmall!.copyWith(color: colors.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Text(label, style: text.labelLarge),
        child,
        if (source case final source?)
          Row(
            spacing: 6,
            children: [
              Icon(UfIcons.arrowElbowDownRight, size: 12, color: colors.muted),
              Flexible(child: Text(source, style: help)),
            ],
          ),
        if (error case final error?)
          Row(
            spacing: 6,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  UfIcons.warningOctagon,
                  size: 13,
                  color: colors.danger,
                ),
              ),
              Flexible(
                child: Text(error, style: help.copyWith(color: colors.danger)),
              ),
            ],
          ),
      ],
    );
  }
}
