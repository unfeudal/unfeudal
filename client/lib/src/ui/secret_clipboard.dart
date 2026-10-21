// SPDX-License-Identifier: Apache-2.0
import 'dart:async';

import 'package:flutter/services.dart';

/// Copies a secret to the clipboard and wipes it 60 seconds later, or on [dispose], if it is still there.
class SecretClipboard {
  Timer? _wipeTimer;
  String? _copied;

  Future<void> copy(String secret) async {
    await Clipboard.setData(ClipboardData(text: secret));
    _copied = secret;
    _wipeTimer?.cancel();
    _wipeTimer = Timer(const Duration(seconds: 60), _wipe);
  }

  // Clears the clipboard only if it still holds the copied secret.
  Future<void> _wipe() async {
    _wipeTimer?.cancel();
    _wipeTimer = null;
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current?.text == _copied) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }

  void dispose() {
    if (_wipeTimer != null) unawaited(_wipe());
  }
}
