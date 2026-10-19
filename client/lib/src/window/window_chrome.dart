// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// The OS window behind the custom title bar; the only file that talks to window_manager.
class WindowChrome with WindowListener {
  WindowChrome._();

  /// Hides the system title bar, then shows the window once Flutter is ready to paint.
  static Future<WindowChrome> start() async {
    await windowManager.ensureInitialized();
    final chrome = WindowChrome._();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        titleBarStyle: TitleBarStyle.hidden,
        minimumSize: Size(720, 520),
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    windowManager.addListener(chrome);
    chrome.maximized.value = await windowManager.isMaximized();
    return chrome;
  }

  final maximized = ValueNotifier(false);
  final focused = ValueNotifier(true);

  Future<void> minimize() => windowManager.minimize();

  Future<void> toggleMaximize() async => await windowManager.isMaximized()
      ? windowManager.unmaximize()
      : windowManager.maximize();

  Future<void> close() => windowManager.close();

  /// Shows and focuses the window, restoring it when minimized (another launch knocked).
  Future<void> bringToFront() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  /// Drags the window from [child]; a double click maximizes or restores it.
  Widget dragArea(Widget child) => DragToMoveArea(child: child);

  @override
  void onWindowMaximize() => maximized.value = true;

  @override
  void onWindowUnmaximize() => maximized.value = false;

  @override
  void onWindowFocus() => focused.value = true;

  @override
  void onWindowBlur() => focused.value = false;
}
