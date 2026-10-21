// SPDX-License-Identifier: Apache-2.0
part of 'home_shell.dart';

extension _ShellKeys on _HomeShellState {
  // Picks the personal vault, then each org in order.
  bool _vaultShortcut(KeyEvent event, HardwareKeyboard keyboard) {
    final index = UfShortcuts.vaultIndex(
      event,
      ctrl: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      meta: keyboard.isMetaPressed,
      inTerminal: _terminalFocus.hasFocus,
    );
    if (index == null) return false;
    final orgs = availableOrgs(_state);
    final vaults = [null, ...?orgs?.orgs.map((o) => o.id)];
    if (index >= vaults.length) return false;
    orgs?.select(vaults[index]);
    _show(null);
    return true;
  }

  KeyEventResult _onLoquetKey(AppState state, KeyEvent e) {
    if (e is KeyDownEvent) {
      state.loquet.show(state.loquet.engine.keyPressed(e.logicalKey));
    }
    // focused itself (a tap on the background), it keeps the arrows from moving the focus
    // away; a focused field or row inside still gets every key
    return _loquetKeys.hasPrimaryFocus
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }
}
