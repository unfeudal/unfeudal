// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../util/email.dart';
import 'errors.dart';

// Every failure is 400 `<field>: <rule>`, never the submitted value.
Never _bad(String field, String rule) =>
    throw ApiError(ApiErrorCode.invalidRequest, '$field: $rule');

/// Trimmed and lowercased; at most 254 code points.
String normalizeEmail(Object? v) {
  if (v is! String) _bad('email', 'must be a string');
  final email = v.trim().toLowerCase();
  if (email.runes.length > 254 || !isEmailAddress(email)) {
    _bad('email', 'must be an email address');
  }
  return email;
}

/// Non-empty, at most [max] code points.
String reqString(Map<String, Object?> m, String key, {int max = 1024}) {
  final v = m[key];
  if (v is! String || v.isEmpty) _bad(key, 'must be a non-empty string');
  if (v.runes.length > max) _bad(key, 'must be at most $max characters');
  return v;
}

Uint8List reqKey32(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is! String) _bad(key, 'must be base64url');
  final Uint8List bytes;
  try {
    bytes = unb64(v);
  } on FormatException {
    _bad(key, 'must be base64url');
  }
  if (bytes.length != 32) _bad(key, 'must be 32 bytes');
  return bytes;
}

/// The model and the KDF bounds; the caller stores the raw map as sent.
AccountBundle parseBundle(Object? raw, {bool allowTestingKdf = false}) {
  try {
    final bundle = AccountBundle.fromJson(raw);
    bundle.kdf.ensureAcceptable(allowTesting: allowTestingKdf);
    return bundle;
  } on FormatException {
    _bad('bundle', 'malformed');
  } on WeakKdf {
    _bad('bundle', 'KDF below the floor');
  } on UnsupportedKdf {
    _bad('bundle', 'unsupported KDF');
  }
}

class DeviceInput {
  DeviceInput(this.name, this.platform);

  final String name;
  final String platform;
}

final _control = RegExp(r'\p{Cc}', unicode: true);

/// Trimmed, 1 to 100 code points, no control character: device, org and team names.
String parseName(Object? v, [String field = 'name']) {
  if (v is! String) _bad(field, 'must be a string');
  final trimmed = v.trim();
  final length = trimmed.runes.length;
  if (length < 1 || length > 100 || _control.hasMatch(trimmed)) {
    _bad(field, 'must be 1 to 100 printable characters');
  }
  return trimmed;
}

DeviceInput parseDevice(Object? raw) {
  if (raw is! Map<String, Object?>) _bad('device', 'must be an object');
  final name = parseName(raw['name'], 'device.name');
  final platform = raw['platform'];
  if (platform is! String || !devicePlatforms.contains(platform)) {
    _bad('device.platform', 'unknown platform');
  }
  return DeviceInput(name, platform);
}

final _ifMatch = RegExp(r'^\s*"?(\d{1,15})"?\s*$');

/// The expected revision; `0` means create.
int parseIfMatch(String? header) {
  final m = header == null ? null : _ifMatch.firstMatch(header);
  if (m == null) _bad('If-Match', 'must be a revision number');
  return int.parse(m[1]!);
}

String parseUuid(String v) {
  if (!isUuid(v)) _bad('id', 'must be a lowercase UUID');
  return v;
}

String parseLocale(Object? v) {
  if (v != 'en' && v != 'fr') _bad('locale', 'must be en or fr');
  return v! as String;
}

/// A changed bundle field outside the route's list (unknown fields included) → 400.
void requireBundleChangeOnly(
  Map<String, Object?> oldRaw,
  Map<String, Object?> newRaw,
  Set<String> allowed,
) {
  const eq = DeepCollectionEquality();
  for (final key in {...oldRaw.keys, ...newRaw.keys}) {
    if (allowed.contains(key)) continue;
    if (oldRaw.containsKey(key) != newRaw.containsKey(key) ||
        !eq.equals(oldRaw[key], newRaw[key])) {
      _bad('bundle', 'field $key cannot change here');
    }
  }
}
