// SPDX-License-Identifier: Apache-2.0

/// UTC with milliseconds, 24 characters: `2026-10-13T12:00:00.000Z`.
String iso(DateTime t) {
  final utc = t.toUtc();
  return utc
      .subtract(Duration(microseconds: utc.microsecond))
      .toIso8601String();
}

final _isoPattern = RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$');

/// Accepts only text that [iso] produces; anything else is a [FormatException].
DateTime parseIso(String s) {
  if (_isoPattern.hasMatch(s)) {
    final t = DateTime.parse(s);
    // DateTime.parse normalises out-of-range fields (month 13 becomes January).
    if (iso(t) == s) return t;
  }
  throw const FormatException('invalid timestamp');
}
