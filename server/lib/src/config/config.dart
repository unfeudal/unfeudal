// SPDX-License-Identifier: AGPL-3.0-or-later
// latest_all keeps the link names (UTC, US/Eastern and others) that latest drops.
import 'package:timezone/data/latest_all.dart';
import 'package:timezone/timezone.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';
import 'package:yaml/yaml.dart';

import '../log/logger.dart';
import '../net/client_ip.dart';
import '../util/email.dart';
import '../version.dart';
import 'features.dart';

part 'config_reader.dart';

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

typedef SmtpConfig = ({
  String host,
  int port,
  SmtpTls tls,
  String? user,
  String? password,
  String from,
});

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
      accessTokenTtl: r.duration('access_token_ttl', '15m', ('1m', '1h')),
      refreshTokenTtl: r.duration('refresh_token_ttl', '30d', ('1d', '365d')),
      loginMaxAttempts: r.count('login_max_attempts', 10, (3, 100)),
      loginLockout: r.duration('login_lockout', '15m', ('1m', '24h')),
      inviteTtl: r.duration('invite_ttl', '7d', ('1h', '30d')),
      maxVaultSize: r.size('max_vault_size', 50 << 20),
      maxOrgSize: r.size('max_org_size', 500 << 20),
      maxOrgsPerUser: r.count('max_orgs_per_user', 0, (0, 10000)),
      maxDevicesPerUser: r.count('max_devices_per_user', 0, (0, 10000)),
      auditRetentionDays: r.count('audit_retention_days', 365, (0, 36500)),
      auditIpRetentionDays: r.count('audit_ip_retention_days', 90, (1, 36500)),
      itemHistoryMaxVersions: r.count('item_history_max_versions', 50, (
        0,
        36500,
      )),
      trashRetentionDays: r.count('trash_retention_days', 30, (0, 36500)),
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
    for (final MapEntry(:key, :value) in _yamlMap(yamlText).entries) {
      if (key == 'features') {
        flags.addAll(_yamlFlags(value));
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
    _addEnv(env, values, flags);
    return (values: values, flags: flags);
  }

  static YamlMap _yamlMap(String? yamlText) {
    final Object? doc;
    try {
      doc = yamlText == null ? null : loadYaml(yamlText);
    } on YamlException catch (e) {
      // the parser's message quotes the offending line, which may hold a secret: only its number
      final line = e.span == null ? '' : ' at line ${e.span!.start.line + 1}';
      throw ConfigError('UNFEUDAL_CONFIG_FILE', 'invalid YAML$line');
    }
    if (doc != null && doc is! YamlMap) {
      throw ConfigError('UNFEUDAL_CONFIG_FILE', 'not a YAML map');
    }
    return doc as YamlMap? ?? YamlMap();
  }

  static Map<Flag, bool> _yamlFlags(Object? value) {
    if (value is! YamlMap) {
      throw ConfigError('features', 'must be a map of flags');
    }
    final flags = <Flag, bool>{};
    for (final MapEntry(key: name, value: on) in value.entries) {
      final flag = Flag.fromWire('$name');
      if (flag == null) throw ConfigError('features.$name', 'unknown flag');
      if (on is! bool) {
        throw ConfigError('features.$name', 'must be true or false');
      }
      flags[flag] = on;
    }
    return flags;
  }

  static void _addEnv(
    Map<String, String> env,
    Map<String, Object> values,
    Map<Flag, bool> flags,
  ) {
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
      values[key] = value;
    }
  }
}
