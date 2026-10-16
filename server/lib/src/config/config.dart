// SPDX-License-Identifier: AGPL-3.0-or-later
// latest_all keeps the link names (UTC, US/Eastern…) that latest drops.
import 'package:timezone/data/latest_all.dart';
import 'package:timezone/timezone.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';
import 'package:yaml/yaml.dart';

import '../log/logger.dart';
import '../net/client_ip.dart';
import '../version.dart';
import 'features.dart';

/// The server refuses to start (exit 2). [message] never contains the value.
class ConfigError implements Exception {
  ConfigError(this.key, this.message);

  final String key;
  final String message;

  @override
  String toString() => 'config: $key: $message';
}

enum OrgCreation { all, instanceOwner }

enum SmtpTls { starttls, implicit, none }

class SmtpConfig {
  SmtpConfig({
    required this.host,
    required this.port,
    required this.tls,
    this.user,
    this.password,
    required this.from,
  });

  final String host;
  final int port;
  final SmtpTls tls;
  final String? user;
  final String? password;
  final String from;
}

/// Instance settings, read once at start from `UNFEUDAL_*` and the YAML file; env wins.
class Config {
  Config._({
    required this.databaseUrl,
    required this.listen,
    required this.publicUrl,
    required this.secretFile,
    required this.sourceUrl,
    required this.trustedProxies,
    required this.logLevel,
    required this.timezone,
    required this.setupToken,
    required this.minClientVersion,
    required this.orgCreation,
    required this.accessTokenTtl,
    required this.refreshTokenTtl,
    required this.loginMaxAttempts,
    required this.loginLockout,
    required this.inviteTtl,
    required this.maxVaultSize,
    required this.maxOrgSize,
    required this.maxOrgsPerUser,
    required this.maxDevicesPerUser,
    required this.auditRetentionDays,
    required this.auditIpRetentionDays,
    required this.itemHistoryMaxVersions,
    required this.trashRetentionDays,
    required this.smtp,
    required this.features,
  });

  factory Config.load(Map<String, String> env, {String? yamlText}) {
    final sources = _sources(env, yamlText);
    final r = _Reader(sources.values);
    final features = Features(sources.flags);
    return Config._(
      databaseUrl: r.databaseUrl('database_url'),
      listen: r.listen('listen'),
      publicUrl: r.publicUrl(features),
      secretFile: r.nonEmpty('secret_file', '/data/secret.key'),
      sourceUrl: r.sourceUrl('source_url'),
      trustedProxies: r.cidrs('trusted_proxies'),
      logLevel: r.logLevel('log_level'),
      timezone: r.timezone('timezone'),
      setupToken: r.setupToken('setup_token'),
      minClientVersion: r.minClientVersion('min_client_version'),
      orgCreation: r.orgCreation('org_creation'),
      accessTokenTtl: r.duration('access_token_ttl', '15m', '1m', '1h'),
      refreshTokenTtl: r.duration('refresh_token_ttl', '30d', '1d', '365d'),
      loginMaxAttempts: r.count('login_max_attempts', 10, 3, 100),
      loginLockout: r.duration('login_lockout', '15m', '1m', '24h'),
      inviteTtl: r.duration('invite_ttl', '7d', '1h', '30d'),
      maxVaultSize: r.size('max_vault_size', 50 << 20),
      maxOrgSize: r.size('max_org_size', 500 << 20),
      maxOrgsPerUser: r.count('max_orgs_per_user', 0, 0, 10000),
      maxDevicesPerUser: r.count('max_devices_per_user', 0, 0, 10000),
      auditRetentionDays: r.count('audit_retention_days', 365, 0, 36500),
      auditIpRetentionDays: r.count('audit_ip_retention_days', 90, 1, 36500),
      itemHistoryMaxVersions: r.count(
        'item_history_max_versions',
        50,
        0,
        36500,
      ),
      trashRetentionDays: r.count('trash_retention_days', 30, 0, 36500),
      smtp: r.smtp(),
      features: features,
    );
  }

  static const keys = [
    'database_url',
    'listen',
    'public_url',
    'secret_file',
    'source_url',
    'trusted_proxies',
    'log_level',
    'timezone',
    'setup_token',
    'min_client_version',
    'org_creation',
    'access_token_ttl',
    'refresh_token_ttl',
    'login_max_attempts',
    'login_lockout',
    'invite_ttl',
    'max_vault_size',
    'max_org_size',
    'max_orgs_per_user',
    'max_devices_per_user',
    'audit_retention_days',
    'audit_ip_retention_days',
    'item_history_max_versions',
    'trash_retention_days',
    'smtp_host',
    'smtp_port',
    'smtp_tls',
    'smtp_user',
    'smtp_password',
    'smtp_from',
  ];

  final String databaseUrl;
  final ({String host, int port}) listen;
  final Uri publicUrl;
  final String secretFile;
  final Uri sourceUrl;
  final List<Cidr> trustedProxies;
  final LogLevel logLevel;
  final String timezone;
  final String? setupToken;
  final String minClientVersion;
  final OrgCreation orgCreation;
  final Duration accessTokenTtl;
  final Duration refreshTokenTtl;
  final int loginMaxAttempts;
  final Duration loginLockout;
  final Duration inviteTtl;
  final int maxVaultSize;
  final int maxOrgSize;
  final int maxOrgsPerUser;
  final int maxDevicesPerUser;
  final int auditRetentionDays;
  final int auditIpRetentionDays;
  final int itemHistoryMaxVersions;
  final int trashRetentionDays;
  final SmtpConfig? smtp;
  final Features features;

  /// Raw values: env wins over YAML; YAML scalars become text, `trusted_proxies` may be a list, null = unset.
  static ({Map<String, Object> values, Map<Flag, bool> flags}) _sources(
    Map<String, String> env,
    String? yamlText,
  ) {
    final values = <String, Object>{};
    final flags = <Flag, bool>{};
    final Object? doc = yamlText == null ? null : loadYaml(yamlText);
    if (doc != null && doc is! YamlMap) {
      throw ConfigError('UNFEUDAL_CONFIG_FILE', 'not a YAML map');
    }
    for (final MapEntry(:key, :value)
        in (doc as YamlMap? ?? YamlMap()).entries) {
      if (key == 'features') {
        if (value is! YamlMap) {
          throw ConfigError('features', 'must be a map of flags');
        }
        for (final MapEntry(key: name, value: on) in value.entries) {
          final flag = Flag.fromWire('$name');
          if (flag == null) throw ConfigError('features.$name', 'unknown flag');
          if (on is! bool) {
            throw ConfigError('features.$name', 'must be true or false');
          }
          flags[flag] = on;
        }
      } else if (!keys.contains(key)) {
        throw ConfigError('$key', 'unknown key');
      } else if (value is YamlList && key == 'trusted_proxies') {
        values['$key'] = [for (final v in value) '$v'];
      } else if (value is YamlList || value is YamlMap) {
        throw ConfigError('$key', 'must be a single value');
      } else if (value != null) {
        values['$key'] = '$value';
      }
    }
    for (final MapEntry(key: name, :value) in env.entries) {
      if (!name.startsWith('UNFEUDAL_') || name == 'UNFEUDAL_CONFIG_FILE') {
        continue;
      }
      if (name.startsWith('UNFEUDAL_FEATURE_')) {
        final flag = Flag.fromWire(name.substring(17).toLowerCase());
        if (flag == null) throw ConfigError(name, 'unknown flag');
        if (value != 'true' && value != 'false') {
          throw ConfigError(name, 'must be true or false');
        }
        flags[flag] = value == 'true';
        continue;
      }
      final key = name.substring(9).toLowerCase();
      if (!keys.contains(key)) throw ConfigError(name, 'unknown variable');
      values[key] = key == 'trusted_proxies'
          ? value
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList()
          : value;
    }
    return (values: values, flags: flags);
  }
}

/// One parser per value kind; every failure names the key, never the value.
class _Reader {
  _Reader(this._values);

  final Map<String, Object> _values;

  static final _duration = RegExp(r'^(\d{1,9})([smhd])$');
  static final _size = RegExp(r'^(\d{1,9})(KB|MB|GB)$');
  static final _count = RegExp(r'^\d{1,9}$');
  static final _setupToken = RegExp(r'^[A-Z2-7]{26}$');

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
    if (!_setupToken.hasMatch(token)) {
      throw ConfigError(key, 'must be 26 base32 characters');
    }
    return token;
  }

  Duration duration(String key, String fallback, String min, String max) {
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

  int count(String key, int fallback, int min, int max) {
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

  static bool _zonesLoaded = false;

  /// An IANA name; times shown in mails only.
  String timezone(String key) {
    final name = _text(key) ?? 'UTC';
    if (!_zonesLoaded) {
      initializeTimeZones();
      _zonesLoaded = true;
    }
    try {
      getLocation(name);
    } on LocationNotFoundException {
      throw ConfigError(key, 'must be an IANA time zone name');
    }
    return name;
  }

  String minClientVersion(String key) {
    final text = _text(key) ?? '0.1.0';
    _orError(key, 'must be X.Y.Z', () => Version.parse(text));
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

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _host = RegExp(r'^[^\s/]+$');

  /// Every given SMTP key is validated; mail is on only with smtp_host, which then requires smtp_from.
  SmtpConfig? smtp() {
    final tls = switch (_text('smtp_tls')) {
      null || 'starttls' => SmtpTls.starttls,
      'implicit' => SmtpTls.implicit,
      'none' => SmtpTls.none,
      _ => throw ConfigError('smtp_tls', 'must be starttls, implicit or none'),
    };
    final port = count(
      'smtp_port',
      tls == SmtpTls.implicit ? 465 : 587,
      1,
      65535,
    );
    final user = limitedText('smtp_user', 256);
    final password = limitedText('smtp_password', 256);
    final from = _text('smtp_from');
    if (from != null && (from.length > 254 || !_email.hasMatch(from))) {
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
    return SmtpConfig(
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

T _orError<T>(String key, String message, T Function() parse) {
  try {
    return parse();
  } on FormatException {
    throw ConfigError(key, message);
  }
}
