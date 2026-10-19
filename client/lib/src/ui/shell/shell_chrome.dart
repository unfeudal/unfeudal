// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/widgets.dart';

/// What the title bar shows over the home screen: the sidebar's live width (null while hidden), the window
/// title and the sidebar toggle. The home shell writes it; the title bar, above the Navigator, reads it.
class ShellChrome extends ChangeNotifier {
  double? _sidebarWidth;
  String? _title;
  VoidCallback? _toggleSidebar;

  double? get sidebarWidth => _sidebarWidth;
  String? get title => _title;
  VoidCallback? get toggleSidebar => _toggleSidebar;

  void show({
    required double? sidebarWidth,
    required String title,
    required VoidCallback toggleSidebar,
  }) {
    if (sidebarWidth == _sidebarWidth && title == _title) {
      _toggleSidebar = toggleSidebar;
      return;
    }
    _sidebarWidth = sidebarWidth;
    _title = title;
    _toggleSidebar = toggleSidebar;
    notifyListeners();
  }

  /// The home shell left: the bar goes back to the access-screen layout.
  void clear() {
    if (_title == null && _sidebarWidth == null) return;
    _sidebarWidth = _title = _toggleSidebar = null;
    notifyListeners();
  }
}

class ShellChromeScope extends InheritedNotifier<ShellChrome> {
  const ShellChromeScope({
    super.key,
    required ShellChrome chrome,
    required super.child,
  }) : super(notifier: chrome);

  static ShellChrome? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellChromeScope>()?.notifier;
}
