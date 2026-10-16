// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

enum LogLevel { debug, info, warn, error }

/// One JSON object per line. Fields go through [redact]; request lines carry
/// only method, path, status, ms and ip.
class Logger {
  Logger(this.level, this.sink);

  final LogLevel level;

  /// Raw output, bypassing redaction: used once to print the setup token.
  final void Function(String line) sink;

  void request({
    required String method,
    required String path,
    required int status,
    required int ms,
    required String ip,
  }) => _write(path == '/healthz' ? LogLevel.debug : LogLevel.info, {
    'method': method,
    'path': path,
    'status': status,
    'ms': ms,
    'ip': ip,
  });

  void info(String msg, [Map<String, Object?> fields = const {}]) =>
      _message(LogLevel.info, msg, fields);

  void warn(String msg, [Map<String, Object?> fields = const {}]) =>
      _message(LogLevel.warn, msg, fields);

  void error(String msg, [Map<String, Object?> fields = const {}]) =>
      _message(LogLevel.error, msg, fields);

  void _message(LogLevel at, String msg, Map<String, Object?> fields) => _write(
    at,
    {'level': at.name, 'msg': msg, ...redact(fields) as Map<String, Object?>},
  );

  void _write(LogLevel at, Map<String, Object?> line) {
    if (at.index >= level.index) sink(jsonEncode(line));
  }
}

final _secretKey = RegExp(
  r'token|authkey|password|passphrase|secret|bundle|private|key|cookie|authorization|envelope|^ct$|nonce|recovery',
  caseSensitive: false,
);
final _uuid = RegExp(
  r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
);
final _base64Run = RegExp(r'[A-Za-z0-9+/_=-]{32,}');
const _hidden = '[redacted]';

/// Hides values under secret-looking keys and any long base64 run; UUIDs stay readable.
Object? redact(Object? value) => switch (value) {
  Map() => {
    for (final e in value.entries)
      '${e.key}': _secretKey.hasMatch('${e.key}') ? _hidden : redact(e.value),
  },
  List() => [for (final v in value) redact(v)],
  String() =>
    _base64Run.hasMatch(value.replaceAll(_uuid, ' ')) ? _hidden : value,
  _ => value,
};
