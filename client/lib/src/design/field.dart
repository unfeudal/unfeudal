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

  /// Where an empty field's value comes from, shown with the folder it is inherited from.
  final String? source;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
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
              Icon(UfIcons.folderSimple, size: 12, color: colors.muted),
              Flexible(
                child: Text(
                  source,
                  style: text.bodySmall!.copyWith(color: colors.muted),
                ),
              ),
            ],
          ),
        if (error case final error?) UfErrorLine(error),
      ],
    );
  }
}

/// An error under a field or a form: the octagon and the message, 12/600 in `danger`.
class UfErrorLine extends StatelessWidget {
  const UfErrorLine(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final danger = UfColors.of(context).danger;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(UfIcons.warningOctagon, size: 13, color: danger),
        ),
        Flexible(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall!
                .copyWith(color: danger, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// [decoration] for a read-only input: no fill and a 14 px `muted` lock at the end.
InputDecoration readOnlyDecoration(
  BuildContext context, [
  InputDecoration decoration = const InputDecoration(),
]) => decoration.copyWith(
  fillColor: Colors.transparent,
  suffixIcon: Icon(UfIcons.lock, size: 14, color: UfColors.of(context).muted),
);

/// A keyboard shortcut written out, as at the end of the search field: mono 11 in a `line` box.
class UfKbd extends StatelessWidget {
  const UfKbd(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: colors.line),
        borderRadius: UfRadius.key,
      ),
      child: Text(
        label,
        style: monoStyle.copyWith(fontSize: 11, color: colors.muted),
      ),
    );
  }
}
