// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../util/email.dart';
import 'errors.dart';

// Every failure is 400 `<field>: <rule>`, never the submitted value.
Never badField(String field, String rule) =>
    throw ApiError.invalid('$field: $rule');

/// Trimmed and lowercased; at most 254 code points.
String normalizeEmail(Object? v) {
  if (v is! String) badField('email', 'must be a string');
  final email = v.trim().toLowerCase();
  if (email.runes.length > 254 || !isEmailAddress(email)) {
    badField('email', 'must be an email address');
  }
  return email;
}

/// Non-empty, at most [max] code points.
String reqString(Map<String, Object?> m, String key, {int max = 1024}) {
  final v = m[key];
  if (v is! String || v.isEmpty) badField(key, 'must be a non-empty string');
  if (v.runes.length > max) badField(key, 'must be at most $max characters');
  return v;
}

Uint8List reqKey32(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is! String) badField(key, 'must be base64url');
  final Uint8List bytes;
  try {
    bytes = unb64(v);
  } on FormatException {
    badField(key, 'must be base64url');
  }
  if (bytes.length != 32) badField(key, 'must be 32 bytes');
  return bytes;
}

/// The raw map as sent, once its model and KDF bounds check out.
Map<String, Object?> parseBundle(
  Object? raw, {
  KdfParams kdfFloor = KdfParams.defaults,
}) {
  try {
    AccountBundle.fromJson(raw).kdf.ensureAcceptable(floor: kdfFloor);
    return raw! as Map<String, Object?>;
  } on FormatException {
    badField('bundle', 'malformed');
  } on WeakKdf {
    badField('bundle', 'KDF below the floor');
  } on UnsupportedKdf {
    badField('bundle', 'unsupported KDF');
  }
}

typedef DeviceInput = ({String name, String platform});

final _control = RegExp(r'\p{Cc}', unicode: true);

/// Trimmed, 1 to 100 code points, no control character: device, org and team names.
String parseName(Object? v, [String field = 'name']) {
  if (v is! String) badField(field, 'must be a string');
  final trimmed = v.trim();
  final length = trimmed.runes.length;
  if (length < 1 || length > 100 || _control.hasMatch(trimmed)) {
    badField(field, 'must be 1 to 100 printable characters');
  }
  return trimmed;
}

DeviceInput parseDevice(Object? raw) {
  if (raw is! Map<String, Object?>) badField('device', 'must be an object');
  final name = parseName(raw['name'], 'device.name');
  final platform = raw['platform'];
  if (platform is! String || !devicePlatforms.contains(platform)) {
    badField('device.platform', 'unknown platform');
  }
  return (name: name, platform: platform);
}

final _ifMatch = RegExp(r'^\s*"?(\d{1,15})"?\s*$');

/// The expected revision; `0` means create.
int parseIfMatch(String? header) {
  final m = header == null ? null : _ifMatch.firstMatch(header);
  if (m == null) badField('If-Match', 'must be a revision number');
  return int.parse(m[1]!);
}

String parseUuid(String v) {
  if (!isUuid(v)) badField('id', 'must be a lowercase UUID');
  return v;
}

OrgRole parseRole(Object? v) =>
    OrgRole.values.asNameMap()[v] ??
    (throw ApiError(
      ApiErrorCode.invalidRequest,
      'role must be owner, admin or member.',
    ));

String parseLocale(Object? v) {
  if (v != 'en' && v != 'fr') badField('locale', 'must be en or fr');
  return v! as String;
}

/// Throws a 400 when a bundle field outside the route's list changes
/// (unknown fields included).
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
      badField('bundle', 'field $key cannot change here');
    }
  }
}
