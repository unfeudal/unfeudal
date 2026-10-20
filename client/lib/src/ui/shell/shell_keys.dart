// SPDX-License-Identifier: Apache-2.0
part of 'home_shell.dart';

extension _ShellKeys on _HomeShellState {
  // Ctrl+1 to Ctrl+9 (Cmd on macOS) picks the personal vault, then each org in order; the terminal keeps its keys.
  bool _vaultShortcut(KeyEvent event, HardwareKeyboard keyboard) {
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    final modifier = mac ? keyboard.isMetaPressed : keyboard.isControlPressed;
    if (event is! KeyDownEvent || !modifier || keyboard.isShiftPressed) {
      return false;
    }
    if (_terminalFocus.hasFocus) return false;
    final digit = _digits.indexOf(event.logicalKey);
    if (digit < 0) return false;
    final orgs = _state.serverInfo.has(Flag.orgs) ? _state.orgs : null;
    final vaults = [null, ...?orgs?.orgs.map((o) => o.id)];
    if (digit >= vaults.length) return false;
    orgs?.select(vaults[digit]);
    _show(null);
    return true;
  }

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  KeyEventResult _onLoquetKey(AppState state, KeyEvent e) {
    if (e is KeyDownEvent) {
      state.loquet.show(state.loquet.engine.key(e.logicalKey));
    }
    // focused itself (a tap on the background), it keeps the arrows from moving the focus
    // away; a focused field or row inside still gets every key
    return _loquetKeys.hasPrimaryFocus
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }
}
