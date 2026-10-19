// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../design/dialog.dart';
import '../design/field.dart';
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
    final colors = UfColors.of(context);
    return UfDialog(
      width: 440,
      title: widget.title,
      actions: [
        CancelButton(onPressed: () => Navigator.pop(context, false)),
        FilledButton(
          key: Key(widget.saveKey),
          onPressed: _busy ? null : _save,
          child: Text(widget.saveLabel),
        ),
      ],
      children: [
        for (final f in widget.fields)
          if (f.kind == FormFieldKind.toggle)
            _TwoChoices(
              key: Key(f.key),
              off: f.offLabel ?? '',
              on: f.label,
              value: _toggles[f.key]!,
              onChanged: (v) => setState(() => _toggles[f.key] = v),
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
        if (_error case final error?)
          Text(
            error,
            style: TextStyle(color: colors.danger, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}

/// Two side-by-side choices in a filled track; the chosen one takes the accent.
class _TwoChoices extends StatelessWidget {
  const _TwoChoices({
    super.key,
    required this.off,
    required this.on,
    required this.value,
    required this.onChanged,
  });

  final String off;
  final String on;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = UfColors.of(context);
    Widget side(String label, bool selected, bool target) => Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? colors.panel : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: UfRadius.control,
            side: selected ? BorderSide(color: colors.line) : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: UfRadius.control,
            onTap: () => onChanged(target),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? colors.text : colors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.neutral,
        borderRadius: UfRadius.card,
      ),
      child: Row(children: [side(off, !value, false), side(on, value, true)]),
    );
  }
}
