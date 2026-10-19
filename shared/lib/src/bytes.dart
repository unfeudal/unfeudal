// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:typed_data';

String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// Strict: url alphabet only, canonical (re-encodes to the same text), so a round-trip is lossless.
Uint8List unb64(String text) {
  final s = text.replaceFirst(RegExp(r'={1,2}$'), '');
  final padded = s.length != text.length;
  if (!RegExp(r'^[A-Za-z0-9_-]*$').hasMatch(s) ||
      s.length % 4 == 1 ||
      (padded && text.length % 4 != 0)) {
    throw const FormatException('invalid base64url');
  }
  final bytes = base64Url.decode(base64Url.normalize(s));
  if (b64(bytes) != s) throw const FormatException('non-canonical base64url');
  return bytes;
}
