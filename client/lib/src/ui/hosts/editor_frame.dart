// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../design/icons.dart';
import '../../design/tokens.dart';

/// The floating editor panel over the terminal: rounded, shadowed, scrolling, with a close button.
class EditorFrame extends StatelessWidget {
  const EditorFrame({
    super.key,
    required this.width,
    required this.children,
    this.onClose,
  });

  final double width;
  final List<Widget> children;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Material(
    color: UfColors.of(context).panel,
    elevation: 8,
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: width,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (onClose != null)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: onClose,
                  icon: const Icon(UfIcons.x),
                ),
              ),
            for (final child in children)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
          ],
        ),
      ),
    ),
  );
}
