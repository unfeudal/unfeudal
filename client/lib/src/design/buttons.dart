// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import 'tokens.dart';

/// 28 px, for toolbars, rows and banners; merged over a button's themed style.
const smallButton = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(0, UfHeight.small)),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
);

/// 40 px, for the single action of an access screen.
const largeButton = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(0, UfHeight.large)),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18)),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: UfRadius.card),
  ),
);

/// Filled danger for a destructive or risky answer: `danger` fill, `onDanger` text.
ButtonStyle dangerButtonStyle(UfColors colors) => ButtonStyle(
  backgroundColor: WidgetStateProperty<Color>.fromMap({
    WidgetState.disabled: colors.disabledBg,
    WidgetState.hovered | WidgetState.pressed: colors.dangerHover,
    WidgetState.any: colors.danger,
  }),
  foregroundColor: WidgetStateProperty<Color>.fromMap({
    WidgetState.disabled: colors.disabledFg,
    WidgetState.any: colors.onDanger,
  }),
);

/// Quiet danger for a destructive action among others: `danger` text, `dangerSoft` on hover.
ButtonStyle dangerQuietStyle(UfColors colors) => ButtonStyle(
  backgroundColor: WidgetStateProperty<Color>.fromMap({
    WidgetState.disabled: Colors.transparent,
    WidgetState.hovered | WidgetState.pressed: colors.dangerSoft,
    WidgetState.any: Colors.transparent,
  }),
  foregroundColor: WidgetStateProperty<Color>.fromMap({
    WidgetState.disabled: colors.disabledFg,
    WidgetState.any: colors.danger,
  }),
);
