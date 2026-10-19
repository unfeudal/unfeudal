// SPDX-License-Identifier: Apache-2.0
import 'dart:typed_data';

import '../bytes.dart';
import '../ids.dart';
import '../time.dart';

/// Typed reads over a decoded JSON object. Every malformed value is a
/// [FormatException] naming `what.key`, never a cast error.
class JsonReader {
  JsonReader(Object? json, this.what)
    : map = json is Map<String, Object?>
          ? json
          : throw FormatException('$what: not a JSON object');

  final String what;
  final Map<String, Object?> map;

  T req<T extends Object>(String key) =>
      opt<T>(key) ?? (throw _error(key, 'missing'));

  /// Absent or null reads as null.
  T? opt<T extends Object>(String key) {
    final value = map[key];
    if (value == null || value is T) return value as T?;
    throw _error(key, 'expected $T');
  }

  int integer(String key, {int min = 0, int? max}) =>
      _inRange(key, req<int>(key), min, max);

  int? optInteger(String key, {int min = 0, int? max}) {
    final value = opt<int>(key);
    return value == null ? null : _inRange(key, value, min, max);
  }

  bool flag(String key, {bool? orElse}) =>
      opt<bool>(key) ?? orElse ?? (throw _error(key, 'missing'));

  /// [max] counts code points. Required text is trimmed, non-empty and
  /// returned trimmed.
  String text(String key, {required int max, bool required = false}) {
    final raw = req<String>(key);
    final value = required ? raw.trim() : raw;
    if (required && value.isEmpty) throw _error(key, 'empty');
    if (value.runes.length > max) throw _error(key, 'longer than $max');
    return value;
  }

  String? optText(String key, {required int max}) =>
      map[key] == null ? null : text(key, max: max);

  String uuid(String key) {
    final value = req<String>(key);
    if (!isUuid(value)) throw _error(key, 'not a UUID');
    return value;
  }

  String? optUuid(String key) => map[key] == null ? null : uuid(key);

  /// Text that [iso] produces.
  DateTime time(String key) {
    final text = req<String>(key);
    try {
      return parseIso(text);
    } on FormatException {
      throw _error(key, 'invalid timestamp');
    }
  }

  DateTime? optTime(String key) => map[key] == null ? null : time(key);

  List<T> list<T extends Object>(String key, {required int max}) {
    final value = req<List<Object?>>(key);
    if (value.length > max) throw _error(key, 'more than $max entries');
    if (!value.every((e) => e is T)) throw _error(key, 'expected List<$T>');
    return List<T>.from(value);
  }

  /// [list], or empty when the key is absent.
  List<T> optList<T extends Object>(String key, {required int max}) =>
      opt<List<Object?>>(key) == null
      ? List<T>.empty()
      : list<T>(key, max: max);

  Map<String, Object?> object(String key) => req<Map<String, Object?>>(key);

  /// Base64url text, exactly [length] bytes when given.
  Uint8List bytes(String key, {int? length}) {
    final text = req<String>(key);
    final Uint8List value;
    try {
      value = unb64(text);
    } on FormatException {
      throw _error(key, 'invalid base64url');
    }
    if (length != null && value.length != length) {
      throw _error(key, 'must be $length bytes');
    }
    return value;
  }

  /// Fields outside [known], kept so newer data survives a round-trip.
  Map<String, Object?> extra(Set<String> known) => {
    for (final entry in map.entries)
      if (!known.contains(entry.key)) entry.key: entry.value,
  };

  int _inRange(String key, int value, int min, int? max) {
    if (value < min || (max != null && value > max)) {
      throw _error(key, 'out of range');
    }
    return value;
  }

  FormatException _error(String key, String problem) =>
      FormatException('$what.$key: $problem');
}
