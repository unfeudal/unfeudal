// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

/// What a trace line is about; `--dart-define=UNFEUDAL_TRACE=http,sync` keeps only those.
enum TraceArea { http, session, sync, ssh, vault, ui }

// `--dart-define=UNFEUDAL_TRACE=all` (or `true`, or a comma list of TraceArea names); off when unset.
const _flag = String.fromEnvironment('UNFEUDAL_TRACE');

final _areas = switch (_flag) {
  '' => const <TraceArea>{},
  'all' || 'true' => TraceArea.values.toSet(),
  _ => {
    for (final name in _flag.split(','))
      ...TraceArea.values.where((a) => a.name == name.trim()),
  },
};

/// Debug and profile builds only; a release build never traces, whatever the flag.
bool tracing(TraceArea area) => !kReleaseMode && _areas.contains(area);

/// One line in the `flutter run` console and in DevTools' Logging view. Ids, kinds, statuses and counts only:
/// never a token, key, password, host name, address, user or any decrypted payload.
void trace(TraceArea area, String message) {
  if (!tracing(area)) return;
  debugPrint('[unfeudal:${area.name}] $message');
  developer.log(message, name: 'unfeudal.${area.name}');
}

/// The first 8 characters of an item id: enough to follow one item through the lines.
String shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);

/// A token's first 6 hex digits of SHA-256: tells two tokens apart without revealing either.
Future<String> tokenTag(String? token) async {
  if (token == null) return '-';
  final digest = await sha256Digest(utf8.encode(token));
  return digest.take(3).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
