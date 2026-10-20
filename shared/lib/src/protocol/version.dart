// SPDX-License-Identifier: Apache-2.0

final _pattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');

// Plain `X.Y.Z`: no prefix, pre-release or build suffix.
List<int> _parse(String s) {
  final match = s.length <= 32 ? _pattern.firstMatch(s) : null;
  if (match == null) throw FormatException('invalid version', s);
  // int.parse throws FormatException on overflow.
  return [for (var i = 1; i <= 3; i++) int.parse(match[i]!)];
}

/// Throws [FormatException] unless both are `X.Y.Z`.
int compareVersions(String a, String b) {
  final x = _parse(a), y = _parse(b);
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return 0;
}

/// [s] with leading zeros dropped (`01.2.3` becomes `1.2.3`); throws [FormatException] unless `X.Y.Z`.
String canonicalVersion(String s) => _parse(s).join('.');
