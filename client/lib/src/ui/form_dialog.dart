// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../design/dialog.dart';
import '../design/field.dart';
import '../design/tokens.dart';
import 'busy_action.dart';

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
  });

  final String key;
  final String label;
  final FormFieldKind kind;
  final int lines;
  final bool mono;

  /// For a toggle: the label of its 'false' side, drawn as a two-choice switch (Ed25519 | RSA 4096).
  final String? offLabel;
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

  Future<void> _save() => run(() async {
    await widget.onSave({
      for (final MapEntry(:key, :value) in _text.entries) key: value.text,
      for (final MapEntry(:key, :value) in _toggles.entries) key: '$value',
    });
    if (mounted) Navigator.pop(context, true);
  });

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    return UfDialog(
      width: 440,
      title: widget.title,
      actions: [
        CancelButton(onPressed: () => Navigator.pop(context, false)),
        FilledButton(
          key: Key(widget.saveKey),
          onPressed: busy ? null : _save,
          child: Text(widget.saveLabel),
        ),
      ],
      children: [
        for (final f in widget.fields)
          if (f.kind == FormFieldKind.toggle)
            SegmentedButton<bool>(
              key: Key(f.key),
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
              segments: [
                ButtonSegment(value: false, label: Text(f.offLabel ?? '')),
                ButtonSegment(value: true, label: Text(f.label)),
              ],
              selected: {_toggles[f.key]!},
              onSelectionChanged: (s) =>
                  setState(() => _toggles[f.key] = s.first),
            )
          else
            UfField(
              label: f.label,
              child: TextField(
                key: Key(f.key),
                controller: _text[f.key],
                obscureText: f.kind == FormFieldKind.secret,
                maxLines: f.kind == FormFieldKind.secret ? 1 : f.lines,
                style: f.mono ? monoStyle.copyWith(fontSize: 12) : null,
              ),
            ),
        if (problem case final error?)
          Text(
            error,
            style: TextStyle(color: colors.danger, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}
