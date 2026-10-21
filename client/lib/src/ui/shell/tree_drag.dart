// SPDX-License-Identifier: Apache-2.0
part of 'tree_panel.dart';

// Hosts and folders move by dragging them onto a folder, a host (its folder) or the Hosts header (the root).
extension _TreeDrag on _TreePanelState {
  // Opens a new host in the selected folder, or the selected host's folder; null without a callback.
  VoidCallback? _newHost(AppState state) => switch (widget.onNewHost) {
    final open? => () => open(_selectedFolder(state)),
    null => null,
  };

  // The selection's folder, when the selection is in the shown vault.
  String? _selectedFolder(AppState state) {
    final e = state.vault?.entry(_selected ?? '');
    if (e == null || e.orgId != state.orgs?.selected) return null;
    return e.kind == ItemKind.folder ? e.id : e.folderId;
  }

  // [row] drags [e] and takes drops [into] a folder (null: the root).
  Widget _movable(
    AppState state,
    VaultEntry e,
    Widget row, {
    required String? into,
  }) => _draggable(state, e, _dropTarget(state, into, row));
  Widget _draggable(AppState state, VaultEntry e, Widget row) {
    if ((state.sync?.isReadOnly ?? true) || e.state != EntryState.ok) {
      return row;
    }
    return Draggable<VaultEntry>(
      data: e,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragChip(name: e.name ?? ''),
      childWhenDragging: Opacity(opacity: 0.4, child: row),
      child: row,
    );
  }

  // Outlines [child] while a host or folder that may move into [folderId] (null: the root) hovers it.
  Widget _dropTarget(AppState state, String? folderId, Widget child) =>
      DragTarget<VaultEntry>(
        onWillAcceptWithDetails: (d) =>
            state.orgs?.canMove(d.data, folderId) ?? false,
        onAcceptWithDetails: (d) => _move(state, d.data, folderId),
        builder: (context, candidates, _) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: UfRadius.control,
            border: Border.all(
              color: candidates.isEmpty
                  ? Colors.transparent
                  : UfColors.of(context).accent,
            ),
          ),
          child: child,
        ),
      );

  Future<void> _move(AppState state, VaultEntry e, String? folderId) async {
    final l = AppLocalizations.of(context);
    try {
      await state.orgs!.moveItem(e, folderId);
    } on Exception catch (error) {
      if (mounted) {
        showUfToast(context, describeError(l, error), tone: UfToastTone.warn);
      }
    }
  }
}

// What follows the pointer while a host or folder is dragged.
class _DragChip extends StatelessWidget {
  const _DragChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return Material(
      color: colors.bg,
      elevation: 4,
      borderRadius: UfRadius.control,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(name, style: _rowStyle(context, true)),
      ),
    );
  }
}
