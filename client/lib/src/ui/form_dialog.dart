// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../design/tokens.dart';
import 'describe_error.dart';

enum FormFieldKind { text, secret, toggle }

/// One field of a [FormDialog]: a (multi-line) text, a secret, or an on/off switch.
class FormDialogField {
  const FormDialogField(
    this.key,
    this.label, {
    this.kind = FormFieldKind.text,
    this.lines = 1,
    this.mono = false,
  });

  final String key;
  final String label;
  final FormFieldKind kind;
  final int lines;
  final bool mono;
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

class _FormDialogState extends State<FormDialog> {
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
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave({
        for (final MapEntry(:key, :value) in _text.entries) key: value.text,
        for (final MapEntry(:key, :value) in _toggles.entries) key: '$value',
      });
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = describeError(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            for (final f in widget.fields)
              if (f.kind == FormFieldKind.toggle)
                SwitchListTile(
                  key: Key(f.key),
                  value: _toggles[f.key]!,
                  onChanged: (v) => setState(() => _toggles[f.key] = v),
                  title: Text(f.label),
                )
              else
                TextField(
                  key: Key(f.key),
                  controller: _text[f.key],
                  obscureText: f.kind == FormFieldKind.secret,
                  maxLines: f.kind == FormFieldKind.secret ? 1 : f.lines,
                  style: f.mono ? monoStyle : null,
                  decoration: InputDecoration(labelText: f.label),
                ),
            if (_error case final error?)
              Text(error, style: TextStyle(color: UfColors.of(context).danger)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: Key(widget.saveKey),
          onPressed: _busy ? null : _save,
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}
