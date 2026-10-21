// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../design/buttons.dart';
import '../design/dialog.dart';
import '../design/field.dart';
import '../design/icons.dart';
import '../design/segmented.dart';
import 'busy_action.dart';
import 'fields.dart';

enum FormFieldKind { text, secret, toggle }

/// One field of a [FormDialog]: a (multi-line) text, a secret, or an on/off switch.
class FormDialogField {
  const FormDialogField(
    this.key,
    this.label, {
    this.kind = FormFieldKind.text,
    this.lines = 1,
    this.mono = false,
    this.offLabel,
    this.autofocus = false,
    this.maxLength,
    this.isRequired = false,
    this.submitOnEnter = false,
    this.fromFile,
  });

  final String key;
  final String label;
  final FormFieldKind kind;
  final int lines;
  final bool mono;

  /// For a toggle: the label of its 'false' side, drawn as a two-choice switch (Ed25519 | RSA 4096).
  final String? offLabel;

  final bool autofocus;
  final int? maxLength;

  /// A text left blank or only spaces stops the save with "required".
  final bool isRequired;
  final bool submitOnEnter;

  /// A button under the field that fills it with a file's text; `open` gives null when no file was picked.
  final ({String label, Future<String?> Function() open})? fromFile;
}

/// A small form in a dialog. [onSave] gets the values by field key (a toggle is "true" or "false");
/// an exception it throws is shown in the dialog, which then stays open. Pops true once saved.
class FormDialog extends StatefulWidget {
  const FormDialog({
    super.key,
    required this.title,
    required this.fields,
    required this.saveKey,
    required this.saveLabel,
    required this.onSave,
    this.initial = const {},
  });

  final String title;
  final List<FormDialogField> fields;
  final String saveKey;
  final String saveLabel;
  final Future<void> Function(Map<String, String> values) onSave;
  final Map<String, String> initial;

  @override
  State<FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<FormDialog> with BusyAction {
  late final _text = {
    for (final f in widget.fields)
      if (f.kind != FormFieldKind.toggle)
        f.key: TextEditingController(text: widget.initial[f.key]),
  };
  late final _toggles = {
    for (final f in widget.fields)
      if (f.kind == FormFieldKind.toggle)
        f.key: widget.initial[f.key] == 'true',
  };

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (widget.fields.any(
      (f) => f.isRequired && _text[f.key]!.text.trim().isEmpty,
    )) {
      return setState(
        () => problem = AppLocalizations.of(context).fieldRequired,
      );
    }
    await run(() async {
      await widget.onSave({
        for (final MapEntry(:key, :value) in _text.entries) key: value.text,
        for (final MapEntry(:key, :value) in _toggles.entries) key: '$value',
      });
      if (mounted) Navigator.pop(context, true);
    });
  }

  Future<void> _fill(String key, Future<String?> Function() open) async {
    final text = await open();
    if (text != null && mounted) _text[key]!.text = text;
  }

  @override
  Widget build(BuildContext context) {
    return UfDialog(
      title: widget.title,
      actions: [
        CancelButton(onPressed: () => Navigator.pop(context, false)),
        BusyButton(
          key: Key(widget.saveKey),
          busy: busy,
          onPressed: _save,
          label: widget.saveLabel,
        ),
      ],
      children: [
        for (final f in widget.fields) ...[
          if (f.kind == FormFieldKind.toggle)
            UfSegmented<bool>(
              key: Key(f.key),
              expand: true,
              segments: [
                (false, Text(f.offLabel ?? '')),
                (true, Text(f.label)),
              ],
              selected: _toggles[f.key]!,
              onChanged: (v) => setState(() => _toggles[f.key] = v),
            )
          else
            keyedField(
              f.key,
              _text[f.key]!,
              f.label,
              secret: f.kind == FormFieldKind.secret,
              mono: f.mono,
              maxLines: f.lines,
              maxLength: f.maxLength,
              autofocus: f.autofocus,
              onSubmitted: f.submitOnEnter ? (_) => _save() : null,
            ),
          if (f.fromFile case final source?)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: Key('${f.key}-file'),
                icon: const Icon(UfIcons.fileArrowUp),
                label: Text(source.label),
                onPressed: () => _fill(f.key, source.open),
              ),
            ),
        ],
        if (problem case final error?) UfErrorLine(error),
      ],
    );
  }
}
