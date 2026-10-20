// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum UfShortcut {
  toggleTree,
  focusSearch,
  newTab,
  closeTab,
  copy,
  paste,
  find,
  reconnect,
}

/// Cmd + B/K/T/W/C/V/F/R on macOS; Ctrl+Shift + the same letters elsewhere, plus plain Ctrl+B/K outside the terminal
/// (inside it, Ctrl+letters belong to the shell).
abstract final class UfShortcuts {
  static final _keys = {
    LogicalKeyboardKey.keyB: UfShortcut.toggleTree,
    LogicalKeyboardKey.keyK: UfShortcut.focusSearch,
    LogicalKeyboardKey.keyT: UfShortcut.newTab,
    LogicalKeyboardKey.keyW: UfShortcut.closeTab,
    LogicalKeyboardKey.keyC: UfShortcut.copy,
    LogicalKeyboardKey.keyV: UfShortcut.paste,
    LogicalKeyboardKey.keyF: UfShortcut.find,
    LogicalKeyboardKey.keyR: UfShortcut.reconnect,
  };

  static UfShortcut? resolve(
    KeyEvent event, {
    required bool ctrl,
    required bool shift,
    required bool meta,
    required bool inTerminal,
  }) {
    if (event is! KeyDownEvent) return null;
    final shortcut = _keys[event.logicalKey];
    if (shortcut == null) return null;
    if (_mac) return meta && !ctrl ? shortcut : null;
    if (!ctrl || meta) return null;
    if (shift) return shortcut;
    final plain =
        shortcut == UfShortcut.toggleTree || shortcut == UfShortcut.focusSearch;
    return plain && !inTerminal ? shortcut : null;
  }

  static String label(UfShortcut shortcut) {
    final letter = _keys.entries
        .firstWhere((e) => e.value == shortcut)
        .key
        .keyLabel
        .toUpperCase();
    return _mac ? '⌘$letter' : 'Ctrl+Shift+$letter';
  }

  /// Ctrl K outside the terminal (Cmd K on macOS); the Ctrl+Shift form is only needed inside it.
  static String get searchLabel => _mac ? '⌘K' : 'Ctrl K';

  /// The vault switch for position [n] (1 to 9).
  static String vaultLabel(int n) => _mac ? '⌘$n' : 'Ctrl $n';

  static bool get _mac => defaultTargetPlatform == TargetPlatform.macOS;
}
