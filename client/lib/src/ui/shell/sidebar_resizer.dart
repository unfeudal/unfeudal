// SPDX-License-Identifier: Apache-2.0
part of 'home_shell.dart';

const _minTree = 220.0, _maxTree = 400.0, _resizeStep = 16.0;

extension _SidebarResizer on _HomeShellState {
  void _saveWidth() => unawaited(
    _state.updateSettings(_state.settings.copyWith(treeWidth: _treeWidth)),
  );

  Widget _resizer() => Focus(
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final step = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowLeft => -_resizeStep,
        LogicalKeyboardKey.arrowRight => _resizeStep,
        _ => null,
      };
      if (step == null) return KeyEventResult.ignored;
      _resize(step);
      _saveWidth();
      return KeyEventResult.handled;
    },
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: const Key('tree-resizer'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => _resize(d.delta.dx),
        onHorizontalDragEnd: (_) => _saveWidth(),
        child: const SizedBox(width: 6, height: double.infinity),
      ),
    ),
  );
}
