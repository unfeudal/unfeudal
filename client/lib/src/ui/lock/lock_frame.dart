// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../design/logo.dart';

/// The lock-screen layout: the mark on the left (Loquet's place), the form on the right.
class LockFrame extends StatelessWidget {
  const LockFrame({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(child: Center(child: UfLogo(size: 260))),
      Expanded(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: children,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
