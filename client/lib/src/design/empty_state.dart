// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../loquet/line_bank.dart';
import '../loquet/loquet_pose.dart';
import '../loquet/loquet_spot.dart';
import 'tokens.dart';

/// A title, one sentence and at most two actions.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    this.primary,
    this.secondary,
    this.mood = LoquetMood.idle,
    this.line,
  });

  final String title;
  final String body;
  final (String, VoidCallback)? primary;
  final (String, VoidCallback)? secondary;
  final LoquetMood mood;
  final LineKey? line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = UfColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LoquetSpot(placement: LoquetPlacement.empty, mood: mood, line: line),
          const SizedBox(height: 18),
          Text(
            title,
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodyMedium!.copyWith(color: colors.muted),
            textAlign: TextAlign.center,
          ),
          if (primary != null || secondary != null) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                if (primary case (final label, final onPressed))
                  FilledButton(onPressed: onPressed, child: Text(label)),
                if (secondary case (final label, final onPressed))
                  OutlinedButton(onPressed: onPressed, child: Text(label)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
