// SPDX-License-Identifier: Apache-2.0
import '../payload/host.dart';

/// `jumpUnresolved`, `jumpLoop` and `keyUnreadable` are raised by the client importer, not by [parseSshConfig].
enum SshConfigWarningKind {
  include,
  match,
  unsupported,
  badValue,
  jumpUnresolved,
  jumpLoop,
  keyUnreadable,
}

class SshConfigWarning {
  const SshConfigWarning(this.line, this.kind, [this.detail]);

  /// 1-based line in the file.
  final int line;
  final SshConfigWarningKind kind;
  final String? detail;
}

class SshConfigHost {
  const SshConfigHost({
    required this.alias,
    required this.hostName,
    required this.port,
    required this.user,
    required this.identityFile,
    required this.proxyJump,
    required this.forwards,
    required this.line,
  });

  final String alias;

  /// `%h` already replaced by [alias].
  final String? hostName;
  final int? port;
  final String? user;

  /// The first `IdentityFile`, unexpanded.
  final String? identityFile;

  /// Hops in order; empty for `ProxyJump none`, null when unset.
  final List<String>? proxyJump;
  final List<PortForward> forwards;

  /// The first `Host` line naming [alias].
  final int line;
}

class SshConfigImport {
  const SshConfigImport(this.hosts, this.warnings);

  final List<SshConfigHost> hosts;
  final List<SshConfigWarning> warnings;
}

const _unsupported = {
  'proxycommand',
  'remoteforward',
  'dynamicforward',
  'certificatefile',
};

class _Section {
  _Section(this.patterns);

  /// Null for the lines before the first `Host`: they match every alias.
  final List<String>? patterns;
  final entries = <(String, Object)>[];
}

/// Reads hosts, jump hosts and local forwards the way ssh does: for each concrete alias, every matching
/// section in file order, the first value of a key wins (forwards add up). `Match` blocks and `Include`
/// are skipped with a warning, as are options that change how the connection is made.
SshConfigImport parseSshConfig(String text) {
  final sections = [_Section(null)];
  final warnings = <SshConfigWarning>[];
  final aliases = <String, int>{};
  var inMatch = false;
  final lines = text.split(RegExp(r'\r?\n'));
  for (var i = 0; i < lines.length; i++) {
    final number = i + 1;
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final pair = RegExp(r'^(\S+?)(?:\s*=\s*|\s+)(.*)$').firstMatch(line);
    if (pair == null) continue;
    final key = pair[1]!.toLowerCase();
    var value = pair[2]!.trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    if (key == 'host') {
      inMatch = false;
      final patterns = value.split(RegExp(r'\s+'));
      sections.add(_Section(patterns));
      for (final p in patterns.where((p) => !p.contains(RegExp(r'[*?!]')))) {
        aliases.putIfAbsent(p, () => number);
      }
      continue;
    }
    if (key == 'match') {
      inMatch = true;
      warnings.add(SshConfigWarning(number, SshConfigWarningKind.match));
      continue;
    }
    if (inMatch) continue;
    if (key == 'include') {
      warnings.add(SshConfigWarning(number, SshConfigWarningKind.include));
    } else if (_unsupported.contains(key)) {
      warnings.add(
        SshConfigWarning(number, SshConfigWarningKind.unsupported, pair[1]),
      );
    } else if (const {
      'hostname',
      'user',
      'identityfile',
      'proxyjump',
      'port',
      'localforward',
    }.contains(key)) {
      final parsed = switch (key) {
        'port' => _port(value),
        'localforward' => _forward(value),
        _ => value,
      };
      if (parsed == null) {
        warnings.add(
          SshConfigWarning(number, SshConfigWarningKind.badValue, pair[1]),
        );
      } else {
        sections.last.entries.add((key, parsed));
      }
    }
  }
  return SshConfigImport([
    for (final MapEntry(key: alias, value: line) in aliases.entries)
      _host(alias, line, sections),
  ], warnings);
}

SshConfigHost _host(String alias, int line, List<_Section> sections) {
  final first = <String, Object>{};
  final forwards = <PortForward>[];
  for (final s in sections.where(
    (s) => s.patterns == null || _matches(alias, s.patterns!),
  )) {
    for (final (key, value) in s.entries) {
      if (key == 'localforward') {
        forwards.add(value as PortForward);
      } else {
        first.putIfAbsent(key, () => value);
      }
    }
  }
  final jump = first['proxyjump'] as String?;
  return SshConfigHost(
    alias: alias,
    hostName: (first['hostname'] as String?)?.replaceAll('%h', alias),
    port: first['port'] as int?,
    user: first['user'] as String?,
    identityFile: first['identityfile'] as String?,
    proxyJump: jump == null
        ? null
        : jump.toLowerCase() == 'none'
        ? <String>[]
        : [for (final hop in jump.split(',')) hop.trim()],
    forwards: forwards,
    line: line,
  );
}

int? _port(String text) {
  final port = int.tryParse(text);
  return port != null && port >= 1 && port <= 65535 ? port : null;
}

// `[bind:]port host:port`; the bind address is dropped.
PortForward? _forward(String text) {
  final parts = text.split(RegExp(r'\s+'));
  if (parts.length != 2) return null;
  final local = _port(parts[0].substring(parts[0].lastIndexOf(':') + 1));
  final colon = parts[1].lastIndexOf(':');
  if (local == null || colon <= 0) return null;
  final remotePort = _port(parts[1].substring(colon + 1));
  if (remotePort == null) return null;
  return PortForward(
    localPort: local,
    remoteHost: parts[1].substring(0, colon).replaceAll(RegExp(r'^\[|\]$'), ''),
    remotePort: remotePort,
    allowLowPorts: local < 1024,
  );
}

bool _matches(String alias, List<String> patterns) {
  var hit = false;
  for (final p in patterns) {
    final negated = p.startsWith('!');
    if (_glob(negated ? p.substring(1) : p).hasMatch(alias)) {
      if (negated) return false; // a negated match excludes the section whatever else matches
      hit = true;
    }
  }
  return hit;
}

RegExp _glob(String p) => RegExp(
  '^${p.split('').map((c) => c == '*'
      ? '.*'
      : c == '?'
      ? '.'
      : RegExp.escape(c)).join()}\$',
);
