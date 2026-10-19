// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../loquet/loquet_pose.dart';
import '../loquet/loquet_spot.dart';
import 'tokens.dart';

/// A title, one sentence and at most one action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    this.primary,
  });

  final String title;
  final String body;
  final (String, VoidCallback)? primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = UfColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LoquetSpot(placement: LoquetPlacement.empty, mood: LoquetMood.idle),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              body,
              style: theme.textTheme.bodyMedium!.copyWith(color: colors.muted),
              textAlign: TextAlign.center,
            ),
          ),
          if (primary case (final label, final onPressed)) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onPressed, child: Text(label)),
          ],
        ],
      ),
    );
  }
}
