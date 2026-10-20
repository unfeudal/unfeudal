// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/widgets.dart';

/// What the title bar shows over the home screen: the sidebar's live width (null while hidden), the window
/// title and the sidebar toggle. The home shell writes it; the title bar, above the Navigator, reads it.
class ShellChrome extends ChangeNotifier {
  double? _sidebarWidth;
  String? _title;
  VoidCallback? _toggleSidebar;

  // The home shell that last wrote it.
  Object? _owner;
  bool _disposed = false;

  double? get sidebarWidth => _sidebarWidth;
  String? get title => _title;
  VoidCallback? get toggleSidebar => _toggleSidebar;

  void show({
    required Object owner,
    required double? sidebarWidth,
    required String title,
    required VoidCallback toggleSidebar,
  }) {
    _owner = owner;
    if (sidebarWidth == _sidebarWidth && title == _title) {
      _toggleSidebar = toggleSidebar;
      return;
    }
    _sidebarWidth = sidebarWidth;
    _title = title;
    _toggleSidebar = toggleSidebar;
    notifyListeners();
  }

  /// [owner] left: the bar goes back to the access-screen layout, unless a newer home shell wrote it since.
  void clear(Object owner) {
    if (_disposed || !identical(owner, _owner)) return;
    _owner = null;
    if (_title == null && _sidebarWidth == null) return;
    _sidebarWidth = _title = _toggleSidebar = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
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
