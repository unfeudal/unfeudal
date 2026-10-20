// SPDX-License-Identifier: Apache-2.0
import '../util/json_reader.dart';
import 'version.dart';

enum Flag {
  orgs('orgs'),
  teams('teams'),
  userOverrides('user_overrides'),
  invitesFromOrgs('invites_from_orgs'),
  smtpInvites('smtp_invites'),
  securityEmails('security_emails'),
  audit('audit'),
  clientEvents('client_events'),
  itemHistory('item_history'),
  recoveryKit('recovery_kit'),
  plainHttpLan('plain_http_lan'),
  reveal('reveal'),
  biometricUnlock('biometric_unlock'),
  sshConfigImport('ssh_config_import'),
  mascot('mascot');

  const Flag(this.wire);

  final String wire;

  static Flag? fromWire(String wire) =>
      values.where((f) => f.wire == wire).firstOrNull;
}

/// `GET /api/info`. [server], [instanceEpoch], [source] and [trashDays] are
/// sent only with a valid access token.
class ApiInfo {
  ApiInfo({
    required this.api,
    required this.minClient,
    required this.latestClient,
    required this.capabilities,
    this.server,
    this.instanceEpoch,
    this.source,
    this.trashDays,
    this.extra = const {},
  });

  factory ApiInfo.fromJson(Object? json) {
    final r = JsonReader(json, 'apiInfo');
    final instanceEpoch = r.opt<String>('instanceEpoch');
    if (instanceEpoch != null && !_epoch.hasMatch(instanceEpoch)) {
      throw const FormatException('apiInfo.instanceEpoch: invalid');
    }
    final server = r.opt<String>('server');
    return ApiInfo(
      api: r.list<int>('api', max: 64),
      minClient: _version(r.req<String>('minClient')),
      latestClient: _version(r.req<String>('latestClient')),
      capabilities: r.list<String>('capabilities', max: 64),
      server: server == null ? null : _version(server),
      instanceEpoch: instanceEpoch,
      source: r.optText('source', max: 2048),
      trashDays: r.optInteger('trashDays'),
      extra: r.extra(const {
        'api',
        'minClient',
        'latestClient',
        'capabilities',
        'server',
        'instanceEpoch',
        'source',
        'trashDays',
      }),
    );
  }

  static final _epoch = RegExp(r'^[A-Za-z0-9_-]{22}$');

  final List<int> api;
  final String minClient;
  final String latestClient;
  final List<String> capabilities;
  final String? server;
  final String? instanceEpoch;
  final String? source;
  final int? trashDays;
  final Map<String, Object?> extra;

  bool has(Flag flag) => capabilities.contains(flag.wire);

  Map<String, Object?> toJson() => {
    ...extra,
    'api': api,
    'minClient': minClient,
    'latestClient': latestClient,
    'capabilities': capabilities,
    if (server != null) 'server': server,
    if (instanceEpoch != null) 'instanceEpoch': instanceEpoch,
    if (source != null) 'source': source,
    if (trashDays != null) 'trashDays': trashDays,
  };

  static String _version(String text) {
    canonicalVersion(text);
    return text;
  }
}
