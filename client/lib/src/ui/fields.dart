// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

/// A labelled text field found by its test key.
TextField keyedField(
  String key,
  TextEditingController controller,
  String label, {
  bool secret = false,
  TextInputType? keyboard,
}) => TextField(
  key: Key(key),
  controller: controller,
  obscureText: secret,
  keyboardType: keyboard,
  decoration: InputDecoration(labelText: label),
);
