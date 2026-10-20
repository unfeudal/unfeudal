// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import 'tokens.dart';

/// 28 px, for toolbars, rows and banners; merged over a button's themed style.
const smallButton = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(0, UfHeight.small)),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
);

/// 40 px with 14 px text, for the single action of an access screen.
ButtonStyle largeButton(TextTheme text) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(0, UfHeight.large)),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18)),
  shape: const WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: UfRadius.card),
  ),
  textStyle: WidgetStatePropertyAll(text.labelLarge!.copyWith(fontSize: 14)),
);

/// Filled danger for a destructive or risky answer: `danger` fill, `onDanger` text.
ButtonStyle dangerButtonStyle(UfColors colors) {
  final ink = WidgetStateProperty<Color>.fromMap({
    WidgetState.disabled: colors.disabledFg,
    WidgetState.any: colors.onDanger,
  });
  return ButtonStyle(
    backgroundColor: WidgetStateProperty<Color>.fromMap({
      WidgetState.disabled: colors.disabledBg,
      WidgetState.pressed: colors.danger,
      WidgetState.hovered: colors.dangerHover,
      WidgetState.any: colors.danger,
    }),
    foregroundColor: ink,
    iconColor: ink,
  );
}

/// Quiet danger for a destructive action among others: `danger` text, `dangerSoft` on hover.
ButtonStyle dangerQuietStyle(UfColors colors) {
  final ink = WidgetStateProperty<Color>.fromMap({
    WidgetState.disabled: colors.disabledFg,
    WidgetState.any: colors.danger,
  });
  return ButtonStyle(
    backgroundColor: WidgetStateProperty<Color>.fromMap({
      WidgetState.disabled: Colors.transparent,
      WidgetState.hovered | WidgetState.pressed: colors.dangerSoft,
      WidgetState.any: Colors.transparent,
    }),
    foregroundColor: ink,
    iconColor: ink,
  );
}

/// A button's label with a 13 px spinner in the button's ink before it while [busy]; the label stays so the
/// button keeps its width.
class BusyLabel extends StatelessWidget {
  const BusyLabel({super.key, required this.busy, required this.label});

  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (!busy) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        SizedBox.square(
          dimension: 13,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: IconTheme.of(context).color,
            backgroundColor: Colors.transparent,
          ),
        ),
        Text(label),
      ],
    );
  }
}

/// A [FilledButton] with a [BusyLabel], disabled while `busy`.
class BusyButton extends FilledButton {
  BusyButton({
    super.key,
    required bool busy,
    required VoidCallback? onPressed,
    required String label,
    super.style,
  }) : super(
         onPressed: busy ? null : onPressed,
         child: BusyLabel(busy: busy, label: label),
       );
}
