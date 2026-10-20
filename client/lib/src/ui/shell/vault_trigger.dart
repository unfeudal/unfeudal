// SPDX-License-Identifier: Apache-2.0
part of 'sidebar.dart';

// The selector itself: an `edge` border on hover, the outer focus ring while its menu is open or it holds
// keyboard focus.
class _VaultTrigger extends StatefulWidget {
  const _VaultTrigger({
    required this.menu,
    required this.name,
    required this.subtitle,
    required this.current,
  });

  final MenuController menu;
  final String name;
  final String subtitle;
  final OrgSummary? current;

  @override
  State<_VaultTrigger> createState() => _VaultTriggerState();
}

class _VaultTriggerState extends State<_VaultTrigger> {
  bool _hover = false, _focus = false;

  @override
  Widget build(BuildContext context) {
    final menu = widget.menu;
    final keyboardFocus =
        _focus &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final l = AppLocalizations.of(context);
    final colors = UfColors.of(context);
    return Semantics(
      button: true,
      label: l.sidebarVaults,
      child: AnimatedContainer(
        duration: UfMotion.of(context).fast,
        decoration: BoxDecoration(
          borderRadius: UfRadius.card,
          boxShadow: menu.isOpen || keyboardFocus
              ? UfElevation.focusRing(colors)
              : null,
        ),
        child: Material(
          color: colors.panel,
          shape: RoundedRectangleBorder(
            borderRadius: UfRadius.card,
            side: BorderSide(
              color: menu.isOpen || _hover ? colors.edge : colors.line,
            ),
          ),
          child: InkWell(
            key: const Key('vault-selector'),
            borderRadius: UfRadius.card,
            hoverColor: Colors.transparent,
            onHover: (hover) => setState(() => _hover = hover),
            onFocusChange: (focus) => setState(() => _focus = focus),
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            child: _VaultTriggerContent(
              name: widget.name,
              subtitle: widget.subtitle,
              current: widget.current,
            ),
          ),
        ),
      ),
    );
  }
}

class _VaultTriggerContent extends StatelessWidget {
  const _VaultTriggerContent({
    required this.name,
    required this.subtitle,
    required this.current,
  });

  final String name;
  final String subtitle;
  final OrgSummary? current;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    final current = this.current;
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          spacing: 10,
          children: [
            VaultTile(
              letter: name,
              personal: current == null,
              awaiting: current != null && !current.isConfirmed,
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge!.copyWith(fontSize: 13.5),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall!.copyWith(
                      color: colors.muted,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Icon(UfIcons.caretUpDown, size: 14, color: colors.muted),
          ],
        ),
      ),
    );
  }
}

/// A vault's first letter on a 28 px tile: `accent` for an org, `neutral` for the personal vault, an edge only
/// while the org awaits confirmation.
class VaultTile extends StatelessWidget {
  const VaultTile({
    super.key,
    required this.letter,
    this.personal = false,
    this.awaiting = false,
  });

  final String letter;
  final bool personal;
  final bool awaiting;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final (fill, ink) = awaiting
        ? (Colors.transparent, colors.muted)
        : personal
        ? (colors.neutral, colors.text)
        : (colors.accent, colors.accentFg);
    return AnimatedContainer(
      duration: UfMotion.of(context).fast,
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: UfRadius.control,
        border: awaiting ? Border.all(color: colors.edge) : null,
      ),
      child: Text(
        String.fromCharCode(letter.runes.first).toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: ink),
      ),
    );
  }
}
