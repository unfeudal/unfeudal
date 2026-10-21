// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:io';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../debug_trace.dart';

/// Loquet's counters and once-keys, kept on this machine only (`loquet.json`); nothing here is synced.
class LoquetMemory {
  LoquetMemory({this._file});

  final File? _file;
  int connections = 0;
  int hostsCreated = 0;
  DateTime? firstUnlock;
  final _once = <String>{};
  Future<void> _saving = Future.value();

  bool hasFired(String key) => _once.contains(key);

  void fire(String key) => _once.add(key);

  /// A missing, unreadable or unknown file gives defaults, rewritten on the next save. Period keys
  /// (`<kind>:<yyyy-mm-dd>`) older than 7 days are dropped.
  static Future<LoquetMemory> load(File file, {required DateTime now}) async {
    final memory = LoquetMemory(file: file);
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?> || json['v'] != 1) return memory;
      final connections = json['connections'], hosts = json['hostsCreated'];
      final first = json['firstUnlock'], once = json['once'];
      if (connections is! int ||
          hosts is! int ||
          once is! List ||
          (first != null && first is! String)) {
        return memory;
      }
      final cutoff = day(now.subtract(const Duration(days: 7)));
      memory
        ..connections = connections
        ..hostsCreated = hosts
        ..firstUnlock = first == null ? null : parseIso(first as String)
        .._once.addAll([
          for (final k in once.whereType<String>())
            if (_periodDay(k) case final d
                when d == null || d.compareTo(cutoff) >= 0)
              k,
        ]);
    } on FileSystemException {
      // missing: defaults
    } on FormatException {
      return LoquetMemory(file: file);
    }
    return memory;
  }

  static String? _periodDay(String key) =>
      RegExp(r':(\d{4}-\d{2}-\d{2})$').firstMatch(key)?.group(1);

  /// Writes through a temporary file; saves never interleave. Without a file, nothing.
  Future<void> save() {
    final file = _file;
    if (file == null) return Future.value();
    final text = jsonEncode({
      'v': 1,
      'connections': connections,
      'hostsCreated': hostsCreated,
      'firstUnlock': firstUnlock == null ? null : iso(firstUnlock!),
      'once': _once.toList()..sort(),
    });
    Future<void> write() async {
      final tmp = File('${file.path}.tmp');
      try {
        await tmp.writeAsString(text, flush: true);
        await tmp.rename(file.path);
      } on FileSystemException catch (e) {
        trace(
          TraceArea.ui,
          'loquet memory: not saved (os error ${e.osError?.errorCode})',
        );
      }
    }

    // A failed write already went to its own caller; the next save still runs.
    return _saving = _saving.then(
      (_) => write(),
      onError: (Object _) => write(),
    );
  }

  /// `yyyy-mm-dd` of [t] as given (local time).
  static String day(DateTime t) => t.toIso8601String().substring(0, 10);
}
