// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import '../design/field.dart';
import '../design/tokens.dart';

/// A labelled text field; its [TextField] carries the test key.
Widget keyedField(
  String key,
  TextEditingController controller,
  String label, {
  bool secret = false,
  bool mono = false,
  TextInputType? keyboard,
  String? hint,
  ValueChanged<String>? onSubmitted,
  String? error,
}) => UfField(
  label: label,
  error: error,
  child: TextField(
    key: Key(key),
    controller: controller,
    obscureText: secret,
    keyboardType: keyboard,
    onSubmitted: onSubmitted,
    style: mono ? monoStyle.copyWith(fontSize: 14) : null,
    decoration: InputDecoration(hintText: hint),
  ),
);
