// SPDX-License-Identifier: Apache-2.0
part of 'inputs.dart';

/// One option of a [UfCombobox]; a [disabledReason] disables it and shows as its sub-text instead of [detail].
class UfComboOption<T> {
  const UfComboOption(
    this.value,
    this.label, {
    this.detail,
    this.disabledReason,
  });

  final T value;
  final String label;
  final String? detail;
  final String? disabledReason;

  bool get isEnabled => disabledReason == null;
}

/// A field you type into to filter a long option list that opens 4 px below it; the match is bold. The arrows
/// move through enabled options, Enter picks, Escape closes. [value] shows its option's label in the field.
class UfCombobox<T> extends StatefulWidget {
  const UfCombobox({
    super.key,
    required this.options,
    required this.onSelected,
    this.value,
    this.hint,
  });

  final List<UfComboOption<T>> options;
  final ValueChanged<T> onSelected;
  final T? value;
  final String? hint;

  @override
  State<UfCombobox<T>> createState() => _UfComboboxState<T>();
}

class _UfComboboxState<T> extends State<UfCombobox<T>>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _activeRow = GlobalKey();
  late final _fade = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.dismissed) _portal.hide();
    });
  late final _fadeCurve = CurvedAnimation(
    parent: _fade,
    curve: UfMotion.enter,
    reverseCurve: UfMotion.exit,
  );
  var _query = '';
  var _active = -1;
  var _width = 0.0;

  List<UfComboOption<T>> get _shown => [
    for (final o in widget.options)
      if (o.label.toLowerCase().contains(_query.toLowerCase())) o,
  ];

  @override
  void initState() {
    super.initState();
    _controller.text = _labelOf(widget.value) ?? '';
    _focus.addListener(() {
      if (!_focus.hasFocus) _close();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = UfMotion.of(context);
    _fade
      ..duration = motion.base
      ..reverseDuration = motion.fast;
  }

  @override
  void didUpdateWidget(UfCombobox<T> old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) {
      _controller.text = _labelOf(widget.value) ?? '';
    }
  }

  @override
  void dispose() {
    _fadeCurve.dispose();
    _fade.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String? _labelOf(T? value) {
    for (final o in widget.options) {
      if (o.value == value) return o.label;
    }
    return null;
  }

  bool get _isOpen => _fade.status.isForwardOrCompleted;

  void _open() {
    if (_isOpen) return;
    _width = context.size?.width ?? 0;
    _portal.show();
    _fade.forward();
  }

  void _close() {
    if (_isOpen) _fade.reverse();
  }

  void _typed(String text) {
    setState(() {
      _query = text;
      _active = _shown.indexWhere((o) => o.isEnabled);
    });
    _open();
  }

  void _pick(UfComboOption<T> option) {
    if (!option.isEnabled) return;
    _controller.text = option.label;
    setState(() => _query = '');
    _close();
    widget.onSelected(option.value);
  }

  void _move(int by) {
    final shown = _shown;
    for (var i = 1; i <= shown.length; i++) {
      final at = (_active + by * i) % shown.length;
      if (shown[at].isEnabled) {
        setState(() => _active = at);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final row = _activeRow.currentContext;
          if (row != null && row.mounted) Scrollable.ensureVisible(row);
        });
        return;
      }
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.arrowUp:
        final by = event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1;
        if (!_isOpen) {
          _open();
          setState(() => _active = _shown.indexWhere((o) => o.isEnabled));
        } else {
          _move(by);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        final shown = _shown;
        if (!_isOpen || _active < 0 || _active >= shown.length) {
          return KeyEventResult.ignored;
        }
        _pick(shown[_active]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape when _isOpen:
        _close();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontSize: 13.5);
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Positioned(
          width: _width,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(0, 4),
            child: TextFieldTapRegion(
              child: FadeTransition(
                opacity: _fadeCurve,
                child: _list(colors, text),
              ),
            ),
          ),
        ),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            onChanged: _typed,
            onTap: _open,
            style: text,
            decoration: InputDecoration(
              hintText: widget.hint,
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 10, right: 8),
                child: Icon(
                  UfIcons.magnifyingGlass,
                  size: 14,
                  color: colors.muted,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(UfColors colors, TextStyle text) {
    final shown = _shown;
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: UfRadius.card,
        boxShadow: UfElevation.floating(colors),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(4),
          child: shown.isEmpty
              ? Center(child: UfNoMatch(query: _query))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 1,
                  children: [
                    for (final (i, option) in shown.indexed)
                      _comboRow(colors, text, option, index: i),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _comboRow(
    UfColors colors,
    TextStyle text,
    UfComboOption<T> option, {
    required int index,
  }) {
    final active = index == _active;
    final sub = option.disabledReason ?? option.detail;
    return Semantics(
      key: active ? _activeRow : null,
      button: true,
      selected: active,
      enabled: option.isEnabled,
      child: MouseRegion(
        cursor: option.isEnabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onEnter: option.isEnabled
            ? (_) => setState(() => _active = index)
            : null,
        child: GestureDetector(
          onTap: () => _pick(option),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: active ? colors.panelHover : null,
              borderRadius: UfRadius.control,
            ),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: UfMatchText(
                    option.label,
                    query: _query,
                    style: text.copyWith(
                      color: option.isEnabled ? colors.text : colors.disabledFg,
                    ),
                  ),
                ),
                if (sub != null)
                  Text(
                    sub,
                    style: text.copyWith(
                      fontSize: 12,
                      color: option.isEnabled
                          ? colors.muted
                          : colors.disabledFg,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
