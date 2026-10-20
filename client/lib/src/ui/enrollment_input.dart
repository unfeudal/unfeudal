// SPDX-License-Identifier: Apache-2.0
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/widgets.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../app_scope.dart';

/// An invite as the user gives it: a pasted [link], or a file picked with [pickFile].
mixin EnrollmentInput<T extends StatefulWidget> on State<T> {
  final link = TextEditingController();
  String? _file;

  /// Replaces the file dialog in tests.
  Future<String?> Function()? get openFile;

  @override
  void dispose() {
    link.dispose();
    super.dispose();
  }

  Future<void> pickFile() async {
    final text = await (openFile ?? _openFileDialog)();
    if (text != null && mounted) setState(() => _file = text);
  }

  /// The picked file when there is one, else the pasted link; throws when neither reads as an enrollment.
  Future<Enrollment> readEnrollment({String? passphrase}) async {
    final file = _file;
    if (file == null) return Enrollment.parseLink(link.text.trim());
    return Enrollment.parseFile(
      file,
      passphrase: passphrase,
      kdfFloor: AppScope.read(context).crypto.kdfFloor,
    );
  }

  static Future<String?> _openFileDialog() async =>
      (await file_selector.openFile())?.readAsString();
}
