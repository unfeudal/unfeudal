// SPDX-License-Identifier: Apache-2.0
part of 'inputs.dart';

/// [text] with every case-insensitive occurrence of [query] in 600.
class UfMatchText extends StatelessWidget {
  const UfMatchText(this.text, {super.key, required this.query, this.style});

  final String text;
  final String query;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final lower = text.toLowerCase(), needle = query.toLowerCase();
    // a lowercase that changes the length would shift the bold run
    if (needle.isEmpty || lower.length != text.length) {
      return Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final spans = <TextSpan>[];
    var from = 0;
    for (
      var at = lower.indexOf(needle);
      at >= 0;
      at = lower.indexOf(needle, from)
    ) {
      if (at > from) spans.add(TextSpan(text: text.substring(from, at)));
      from = at + needle.length;
      spans.add(
        TextSpan(
          text: text.substring(at, from),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
    }
    if (from < text.length) spans.add(TextSpan(text: text.substring(from)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// No result for [query]: Loquet searching at 40 px over the localized "nothing matches" line, quoting the query, in 13 muted, centred.
class UfNoMatch extends StatelessWidget {
  const UfNoMatch({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        const LoquetSpot(
          placement: LoquetPlacement.dialog,
          mood: LoquetMood.search,
        ),
        Text(
          AppLocalizations.of(context).searchNoMatch(query),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium!
              .copyWith(fontSize: 13, color: UfColors.of(context).muted),
        ),
      ],
    ),
  );
}

/// A search box: a muted magnifier, then the text, then a kbd chip showing [shortcut] at rest and Esc while
/// focused; the shortcut hides once the field holds text. Escape clears the text, then calls [onEscape], which
/// defaults to leaving the field.
class UfSearchField extends StatefulWidget {
  const UfSearchField({
    super.key,
    this.focusNode,
    this.hint,
    this.shortcut,
    this.onChanged,
    this.onEscape,
    this.autofocus = false,
  });

  final FocusNode? focusNode;
  final String? hint;

  /// The shortcut that reaches the field, written out ("Ctrl K"); null shows no chip at rest.
  final String? shortcut;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEscape;
  final bool autofocus;

  @override
  State<UfSearchField> createState() => _UfSearchFieldState();
}

class _UfSearchFieldState extends State<UfSearchField> {
  final _controller = TextEditingController();
  FocusNode? _ownFocus;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    _controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(UfSearchField old) {
    super.didUpdateWidget(old);
    final oldFocus = old.focusNode ?? _ownFocus;
    if (oldFocus != _focus) {
      oldFocus?.removeListener(_refresh);
      _focus.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_refresh);
    _controller.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent || event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_controller.text.isNotEmpty) {
      _controller.clear();
      widget.onChanged?.call('');
    } else if (widget.onEscape case final escape?) {
      escape();
    } else {
      _focus.unfocus();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final muted = UfColors.of(context).muted;
    final kbd = _focus.hasFocus
        ? AppLocalizations.of(context).keyEscape
        : _controller.text.isEmpty
        ? widget.shortcut
        : null;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 13.5),
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 10, right: 8),
            child: Icon(UfIcons.magnifyingGlass, size: 14, color: muted),
          ),
          prefixIconConstraints: const BoxConstraints(),
          suffixIcon: kbd == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: UfKbd(kbd),
                ),
          suffixIconConstraints: const BoxConstraints(),
        ),
      ),
    );
  }
}
