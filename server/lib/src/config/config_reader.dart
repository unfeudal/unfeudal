// SPDX-License-Identifier: AGPL-3.0-or-later
part of 'config.dart';

// One parser per value kind; every failure names the key, never the value.
class _Reader {
  _Reader(this._values);

  final Map<String, Object> _values;

  static final _duration = RegExp(r'^(\d{1,9})([smhd])$');
  static final _size = RegExp(r'^(\d{1,9})(KB|MB|GB)$');
  static final _count = RegExp(r'^\d{1,9}$');

  String? _text(String key) => switch (_values[key]) {
    final String s => s,
    final List<String> l => l.join(','),
    _ => null,
  };

  Uri publicUrl(Features features) {
    final text = _text('public_url');
    if (text == null) throw ConfigError('public_url', 'required');
    final uri = Uri.tryParse(text);
    final isHttps = uri?.scheme == 'https';
    final isLanHttp =
        uri?.scheme == 'http' &&
        features.enabled(Flag.plainHttpLan) &&
        isLanHost(uri!);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !(isHttps || isLanHttp)) {
      throw ConfigError(
        'public_url',
        'must be an https URL (http only on a LAN host with plain_http_lan)',
      );
    }
    return uri;
  }

  List<Cidr> cidrs(String key) {
    final raw = _values[key];
    final items = raw is List<String>
        ? raw
        : (raw as String? ?? '')
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty);
    return [
      for (final item in items)
        _orError(key, 'must be a list of CIDRs', () => Cidr.parse(item)),
    ];
  }

  LogLevel logLevel(String key) {
    final text = _text(key);
    if (text == null) return LogLevel.info;
    return LogLevel.values.asNameMap()[text] ??
        (throw ConfigError(key, 'must be debug, info, warn or error'));
  }

  String? setupToken(String key) {
    final text = _text(key);
    if (text == null) return null;
    final token = normalizeSetupToken(text);
    if (!isSetupToken(token)) {
      throw ConfigError(key, 'must be 26 base32 characters');
    }
    return token;
  }

  Duration duration(String key, String fallback, (String, String) range) {
    final (min, max) = range;
    Duration parse(String text) {
      final m = _duration.firstMatch(text);
      if (m == null) {
        throw ConfigError(key, 'must be a duration between $min and $max');
      }
      final n = int.parse(m[1]!);
      return switch (m[2]) {
        's' => Duration(seconds: n),
        'm' => Duration(minutes: n),
        'h' => Duration(hours: n),
        _ => Duration(days: n),
      };
    }

    final value = parse(_text(key) ?? fallback);
    if (value < parse(min) || value > parse(max)) {
      throw ConfigError(key, 'must be a duration between $min and $max');
    }
    return value;
  }

  /// Binary units (1 MB = 1 048 576 bytes); `0` means unlimited.
  int size(String key, int fallback) {
    final text = _text(key);
    if (text == null) return fallback;
    if (text == '0') return 0;
    final m = _size.firstMatch(text);
    if (m == null) throw ConfigError(key, 'must be 0 or <int>KB, MB or GB');
    final shift = switch (m[2]) {
      'KB' => 10,
      'MB' => 20,
      _ => 30,
    };
    return int.parse(m[1]!) << shift;
  }

  int count(String key, int fallback, (int, int) range) {
    final (min, max) = range;
    final text = _text(key);
    if (text == null) return fallback;
    final value = _count.hasMatch(text) ? int.parse(text) : -1;
    if (value < min || value > max) {
      throw ConfigError(key, 'must be an integer between $min and $max');
    }
    return value;
  }

  /// `sqlite:///<path>`, or `postgres://host/database` with sslmode absent, disable, require or verify-full.
  String databaseUrl(String key) {
    final text = _text(key) ?? 'sqlite:///data/unfeudal.db';
    if (text.startsWith('sqlite:///') && text.length > 'sqlite:///'.length) {
      return text;
    }
    final uri = Uri.tryParse(text);
    final sslMode = uri?.queryParameters['sslmode'];
    if (uri == null ||
        uri.scheme != 'postgres' ||
        uri.host.isEmpty ||
        uri.pathSegments.isEmpty ||
        uri.pathSegments.first.isEmpty ||
        !(sslMode == null || _sslModes.contains(sslMode))) {
      throw ConfigError(
        key,
        'must be sqlite:///<path> or postgres://host/database',
      );
    }
    return text;
  }

  static const _sslModes = {'disable', 'require', 'verify-full'};

  ({String host, int port}) listen(String key) {
    final text = _text(key) ?? '0.0.0.0:8080';
    final colon = text.lastIndexOf(':');
    final host = colon < 0
        ? ''
        : text.substring(0, colon).replaceAll(RegExp(r'^\[|\]$'), '');
    final portText = colon < 0 ? '' : text.substring(colon + 1);
    final port = _count.hasMatch(portText) ? int.parse(portText) : 0;
    if (host.isEmpty || port < 1 || port > 65535) {
      throw ConfigError(key, 'must be host:port');
    }
    return (host: host, port: port);
  }

  String nonEmpty(String key, String fallback) {
    final text = _text(key) ?? fallback;
    if (text.isEmpty) throw ConfigError(key, 'must not be empty');
    return text;
  }

  Uri sourceUrl(String key) {
    final uri = Uri.tryParse(
      _text(key) ?? 'https://github.com/unfeudal/unfeudal',
    );
    if (uri == null ||
        !(uri.scheme == 'https' || uri.scheme == 'http') ||
        uri.host.isEmpty) {
      throw ConfigError(key, 'must be an http(s) URL');
    }
    return uri;
  }

  /// An IANA name; times shown in mails only.
  String timezone(String key) {
    final name = _text(key) ?? 'UTC';
    try {
      timeZoneNamed(name);
    } on LocationNotFoundException {
      throw ConfigError(key, 'must be an IANA time zone name');
    }
    return name;
  }

  String minClientVersion(String key) {
    final text = _text(key) ?? '0.1.0';
    _orError(key, 'must be X.Y.Z', () => canonicalVersion(text));
    if (compareVersions(text, latestClientVersion) > 0) {
      throw ConfigError(key, 'must not exceed $latestClientVersion');
    }
    return text;
  }

  OrgCreation orgCreation(String key) => switch (_text(key)) {
    null || 'all' => OrgCreation.all,
    'instance_owner' => OrgCreation.instanceOwner,
    _ => throw ConfigError(key, 'must be all or instance_owner'),
  };

  static final _host = RegExp(r'^[^\s/]+$');

  /// Every given SMTP key is validated; mail is on only with smtp_host, which then requires smtp_from.
  SmtpConfig? smtp() {
    final tls = switch (_text('smtp_tls')) {
      null || 'starttls' => SmtpTls.starttls,
      'implicit' => SmtpTls.implicit,
      'none' => SmtpTls.none,
      _ => throw ConfigError('smtp_tls', 'must be starttls, implicit or none'),
    };
    final defaultPort = tls == SmtpTls.implicit ? 465 : 587;
    final port = count('smtp_port', defaultPort, (1, 65535));
    final user = limitedText('smtp_user', 256);
    final password = limitedText('smtp_password', 256);
    final from = _text('smtp_from');
    if (from != null && (from.length > 254 || !isEmailAddress(from))) {
      throw ConfigError('smtp_from', 'must be an email address');
    }
    final host = _text('smtp_host');
    if (host == null) return null;
    if (!_host.hasMatch(host)) {
      throw ConfigError('smtp_host', 'must be a host name or IP');
    }
    if (from == null) {
      throw ConfigError('smtp_from', 'required with smtp_host');
    }
    return (
      host: host,
      port: port,
      tls: tls,
      user: user,
      password: password,
      from: from,
    );
  }

  String? limitedText(String key, int max) {
    final text = _text(key);
    if (text != null && text.runes.length > max) {
      throw ConfigError(key, 'must be at most $max characters');
    }
    return text;
  }
}

bool _zonesLoaded = false;

/// The IANA zone [name]; the zone database loads on first use.
Location timeZoneNamed(String name) {
  if (!_zonesLoaded) {
    initializeTimeZones();
    _zonesLoaded = true;
  }
  return getLocation(name);
}

T _orError<T>(String key, String message, T Function() parse) {
  try {
    return parse();
  } on FormatException {
    throw ConfigError(key, message);
  }
}
