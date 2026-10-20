// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../l10n/app_localizations.dart';
import '../design/field.dart';
import '../design/icons.dart';
import '../design/inputs.dart';
import '../design/tokens.dart';

/// A labelled text field; its [TextField] carries the test key. A [secret] one has an eye to show its text,
/// keyed `<key>-peek`; a [strength] one (a new password) has the strength meter under it. Without a [label]
/// the field stands alone.
Widget keyedField(
  String key,
  TextEditingController controller,
  String? label, {
  bool secret = false,
  bool strength = false,
  bool mono = false,
  bool enabled = true,
  bool autofocus = false,
  TextInputType? keyboard,
  String? hint,
  int? minLines,
  int maxLines = 1,
  int? maxLength,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  String? error,
}) {
  final input = _KeyedInput(
    fieldKey: key,
    controller: controller,
    secret: secret,
    mono: mono,
    enabled: enabled,
    autofocus: autofocus,
    keyboard: keyboard,
    hint: hint,
    minLines: minLines,
    maxLines: maxLines,
    maxLength: maxLength,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
  );
  final field = strength
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [input, _PasswordStrength(controller)],
        )
      : input;
  return label == null
      ? field
      : UfField(label: label, error: error, child: field);
}

/// 0 when empty, 1 under the minimum length, then up to 4 with length and character classes.
int passwordScore(String password) {
  // ponytail: length and classes only, blind to dictionary words and patterns; zxcvbn-like scoring if
  // users need real guidance
  final length = passwordLength(password);
  if (length == 0) return 0;
  if (length < AccountCrypto.minPasswordLength) return 1;
  final classes = [
    RegExp('[a-z]'),
    RegExp('[A-Z]'),
    RegExp(r'\d'),
    RegExp(r'[^a-zA-Z\d]'),
  ].where((c) => c.hasMatch(password)).length;
  return 2 + (length >= 12 ? 1 : 0) + (length >= 16 || classes >= 3 ? 1 : 0);
}

// The strength meter of the controller's password and the Caps Lock state, kept current as keys go down.
class _PasswordStrength extends StatefulWidget {
  const _PasswordStrength(this.controller);

  final TextEditingController controller;

  @override
  State<_PasswordStrength> createState() => _PasswordStrengthState();
}

class _PasswordStrengthState extends State<_PasswordStrength> {
  bool _capsLock = _capsLockOn;

  static bool get _capsLockOn => HardwareKeyboard.instance.lockModesEnabled
      .contains(KeyboardLockMode.capsLock);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  void _refresh() => setState(() {});

  // Reads the lock state only; the key goes on to the focused field.
  bool _onKey(KeyEvent _) {
    if (_capsLockOn != _capsLock) setState(() => _capsLock = _capsLockOn);
    return false;
  }

  @override
  Widget build(BuildContext context) => UfStrengthMeter(
    score: passwordScore(widget.controller.text),
    capsLock: _capsLock,
  );
}

class _KeyedInput extends StatefulWidget {
  const _KeyedInput({
    required this.fieldKey,
    required this.controller,
    required this.secret,
    required this.mono,
    required this.enabled,
    required this.autofocus,
    this.keyboard,
    this.hint,
    this.minLines,
    required this.maxLines,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
  });

  final String fieldKey;
  final TextEditingController controller;
  final bool secret, mono, enabled, autofocus;
  final TextInputType? keyboard;
  final String? hint;
  final int? minLines;
  final int maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_KeyedInput> createState() => _KeyedInputState();
}

class _KeyedInputState extends State<_KeyedInput> {
  bool _peeking = false;

  @override
  Widget build(BuildContext context) => TextField(
    key: Key(widget.fieldKey),
    controller: widget.controller,
    obscureText: widget.secret && !_peeking,
    enabled: widget.enabled,
    autofocus: widget.autofocus,
    keyboardType: widget.keyboard,
    minLines: widget.minLines,
    maxLines: widget.maxLines,
    maxLength: widget.maxLength,
    onChanged: widget.onChanged,
    onSubmitted: widget.onSubmitted,
    style: widget.mono ? monoField : null,
    decoration: InputDecoration(
      hintText: widget.hint,
      counterText: widget.maxLength == null ? null : '',
      suffixIcon: widget.secret
          ? IconButton(
              key: Key('${widget.fieldKey}-peek'),
              tooltip: AppLocalizations.of(context).unlockPeek,
              icon: Icon(_peeking ? UfIcons.eyeSlash : UfIcons.eye),
              color: _peeking ? UfColors.of(context).accentText : null,
              onPressed: () => setState(() => _peeking = !_peeking),
            )
          : null,
    ),
  );
}
