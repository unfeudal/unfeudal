// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../design/dialog.dart';
import '../../design/field.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../vault/vault.dart';

/// A labelled dropdown of [entries] after a [none] item; a [value] not among them shows as [none].
Widget entryPicker({
  required String key,
  required String label,
  required String none,
  required List<VaultEntry> entries,
  required String? value,
  required ValueChanged<String?>? onChanged,
  String? source,
}) => UfField(
  label: label,
  source: source,
  child: DropdownButtonFormField<String?>(
    key: Key(key),
    initialValue: entries.any((e) => e.id == value) ? value : null,
    items: [
      DropdownMenuItem(key: Key('$key-root'), child: Text(none)),
      for (final e in entries)
        DropdownMenuItem(
          key: Key('$key-${e.id}'),
          value: e.id,
          child: Text(e.name ?? ''),
        ),
    ],
    onChanged: onChanged,
  ),
);

/// The floating editor over the terminals: where the item lives and its name, the fields, then trash on the
/// left and Cancel / Save on the right. Read-only items show [notice] and no footer.
class EditorFrame extends StatelessWidget {
  const EditorFrame({
    super.key,
    required this.title,
    this.crumb,
    this.notice,
    required this.children,
    this.onClose,
    this.save,
    this.trash,
  });

  static const width = 420.0;
  final String title;

  /// "Personnel / Maison".
  final String? crumb;
  final String? notice;
  final List<Widget> children;
  final VoidCallback? onClose;
  final Widget? save;
  final Widget? trash;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    final text = Theme.of(context).textTheme;
    final close = MaterialLocalizations.of(context);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 60,
            offset: Offset(0, 24),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        if (crumb case final crumb?)
                          Text(
                            crumb,
                            style: text.labelSmall!.copyWith(
                              color: colors.muted,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        Text(
                          title,
                          style: text.headlineMedium!.copyWith(fontSize: 24),
                        ),
                      ],
                    ),
                  ),
                  if (onClose != null)
                    IconButton(
                      tooltip: close.closeButtonTooltip,
                      onPressed: onClose,
                      icon: const Icon(UfIcons.x, size: 18),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                children: [
                  if (notice case final notice?)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors.warnSoft,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(10),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 8,
                        children: [
                          Icon(
                            UfIcons.warning,
                            size: 15,
                            color: colors.warnText,
                          ),
                          Expanded(
                            child: Text(
                              notice,
                              style: text.bodySmall!.copyWith(
                                color: colors.warnText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final child in children)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: child,
                    ),
                ],
              ),
            ),
            if (save != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 20, 16),
                child: Row(
                  spacing: 8,
                  children: [
                    if (trash case final trash?)
                      TextButtonTheme(
                        data: TextButtonThemeData(
                          style: TextButton.styleFrom(
                            foregroundColor: colors.danger,
                          ).merge(Theme.of(context).textButtonTheme.style),
                        ),
                        child: trash,
                      ),
                    const Spacer(),
                    if (onClose != null) CancelButton(onPressed: onClose),
                    save!,
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
