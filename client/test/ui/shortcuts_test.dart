// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/ui/shell/shortcuts.dart';

KeyDownEvent down(LogicalKeyboardKey k) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: k,
  timeStamp: Duration.zero,
);

void main() {
  test(
    'Windows: Ctrl+Shift everywhere, plain Ctrl+B/K only outside the terminal',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        UfShortcuts.resolve(
          down(LogicalKeyboardKey.keyB),
          ctrl: true,
          shift: true,
          meta: false,
          inTerminal: true,
        ),
        UfShortcut.toggleTree,
      );
      expect(
        UfShortcuts.resolve(
          down(LogicalKeyboardKey.keyB),
          ctrl: true,
          shift: false,
          meta: false,
          inTerminal: true,
        ),
        isNull,
      );
      expect(
        UfShortcuts.resolve(
          down(LogicalKeyboardKey.keyK),
          ctrl: true,
          shift: false,
          meta: false,
          inTerminal: false,
        ),
        UfShortcut.focusSearch,
      );
      expect(
        UfShortcuts.resolve(
          down(LogicalKeyboardKey.keyT),
          ctrl: true,
          shift: false,
          meta: false,
          inTerminal: false,
        ),
        isNull,
      );
      expect(
        UfShortcuts.resolve(
          down(LogicalKeyboardKey.keyW),
          ctrl: true,
          shift: true,
          meta: false,
          inTerminal: true,
        ),
        UfShortcut.closeTab,
      );
      expect(UfShortcuts.label(UfShortcut.focusSearch), 'Ctrl+Shift+K');
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test('macOS: Cmd everywhere', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    for (final (k, s) in [
      (LogicalKeyboardKey.keyB, UfShortcut.toggleTree),
      (LogicalKeyboardKey.keyK, UfShortcut.focusSearch),
      (LogicalKeyboardKey.keyT, UfShortcut.newTab),
      (LogicalKeyboardKey.keyW, UfShortcut.closeTab),
    ]) {
      expect(
        UfShortcuts.resolve(
          down(k),
          ctrl: false,
          shift: false,
          meta: true,
          inTerminal: true,
        ),
        s,
      );
    }
    expect(UfShortcuts.label(UfShortcut.focusSearch), '⌘K');
    debugDefaultTargetPlatformOverride = null;
  });

  test('terminal shortcuts: Ctrl+Shift or Cmd only; plain Ctrl+C/V/F/R stay the shell\'s', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    for (final (k, s) in [
      (LogicalKeyboardKey.keyC, UfShortcut.copy),
      (LogicalKeyboardKey.keyV, UfShortcut.paste),
      (LogicalKeyboardKey.keyF, UfShortcut.find),
      (LogicalKeyboardKey.keyR, UfShortcut.reconnect),
    ]) {
      expect(
        UfShortcuts.resolve(
          down(k),
          ctrl: true,
          shift: true,
          meta: false,
          inTerminal: true,
        ),
        s,
      );
      expect(
        UfShortcuts.resolve(
          down(k),
          ctrl: true,
          shift: false,
          meta: false,
          inTerminal: true,
        ),
        isNull,
      );
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(
      UfShortcuts.resolve(
        down(LogicalKeyboardKey.keyV),
        ctrl: false,
        shift: false,
        meta: true,
        inTerminal: true,
      ),
      UfShortcut.paste,
    );
    expect(
      UfShortcuts.resolve(
        down(LogicalKeyboardKey.keyC),
        ctrl: true,
        shift: false,
        meta: false,
        inTerminal: true,
      ),
      isNull,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
