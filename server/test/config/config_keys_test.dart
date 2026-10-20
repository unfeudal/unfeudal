// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/config/config.dart';
import 'package:unfeudal_server/src/log/logger.dart';

const base = {'UNFEUDAL_PUBLIC_URL': 'https://vault.test'};
Config load(Map<String, String> env) => Config.load({...base, ...env});
Matcher errorOn(String key) =>
    throwsA(isA<ConfigError>().having((e) => e.key, 'key', key));
String env(String key) => 'UNFEUDAL_${key.toUpperCase()}';

void main() {
  group('documented defaults', () {
    late Config c;
    setUp(() => c = load(const {}));

    test('database, listen address, public URL and secret file', () {
      expect(c.databaseUrl, 'sqlite:///data/unfeudal.db');
      expect((c.listen.host, c.listen.port), ('0.0.0.0', 8080));
      expect(
        (c.publicUrl, c.secretFile),
        (Uri.parse('https://vault.test'), '/data/secret.key'),
      );
    });

    test('source URL, proxies, log level, timezone and setup token', () {
      expect(c.sourceUrl, Uri.parse('https://github.com/unfeudal/unfeudal'));
      expect(c.trustedProxies, isEmpty);
      expect(
        (c.logLevel, c.timezone, c.setupToken),
        (LogLevel.info, 'UTC', null),
      );
    });

    test('client version and org creation', () {
      expect((c.minClientVersion, c.orgCreation), ('0.1.0', OrgCreation.all));
    });

    test('token lifetimes, login lockout and invite lifetime', () {
      expect(
        (c.accessTokenTtl, c.refreshTokenTtl),
        (const Duration(minutes: 15), const Duration(days: 30)),
      );
      expect(
        (c.loginMaxAttempts, c.loginLockout, c.inviteTtl),
        (10, const Duration(minutes: 15), const Duration(days: 7)),
      );
    });

    test('storage and count limits', () {
      expect(
        (c.maxVaultSize, c.maxOrgSize, c.maxOrgsPerUser, c.maxDevicesPerUser),
        (50 << 20, 500 << 20, 0, 0),
      );
    });

    test('retention', () {
      expect(
        (
          c.auditRetentionDays,
          c.auditIpRetentionDays,
          c.itemHistoryMaxVersions,
          c.trashRetentionDays,
        ),
        (365, 90, 50, 30),
      );
    });

    test('no SMTP', () {
      expect(c.smtp, isNull);
    });
  });

  test('accepted values', () {
    final c = load({
      env('database_url'): 'postgres://u:p@db:5432/unfeudal?sslmode=require',
      env('listen'): '[::]:9000',
      env('setup_token'): 'abcd-efgh ijkl-mnop-qrst-uvwx-yz',
      env('timezone'): 'Europe/Paris',
      env('org_creation'): 'instance_owner',
      env('min_client_version'): '0.0.9',
      env('audit_retention_days'): '0',
      env('item_history_max_versions'): '0',
      env('trash_retention_days'): '36500',
      env('max_devices_per_user'): '10000',
    });
    expect(
      (c.listen.host, c.listen.port, c.setupToken),
      ('::', 9000, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'),
    );
    expect(
      (c.timezone, c.orgCreation, c.auditRetentionDays),
      ('Europe/Paris', OrgCreation.instanceOwner, 0),
    );
    expect(
      load({env('database_url'): 'sqlite:///var/lib/u.db'}).databaseUrl,
      'sqlite:///var/lib/u.db',
    );
  });

  test('plain http public_url only on a LAN host with plain_http_lan', () {
    expect(
      load({
        env('public_url'): 'http://192.168.1.10:8080',
        'UNFEUDAL_FEATURE_PLAIN_HTTP_LAN': 'true',
      }).publicUrl.port,
      8080,
    );
    expect(
      () => load({env('public_url'): 'http://192.168.1.10'}),
      errorOn('public_url'),
      reason: 'plain_http_lan is off by default',
    );
  });

  test('SMTP: off without host, ports follow smtp_tls, from required', () {
    final smtp = {
      env('smtp_host'): 'smtp.test',
      env('smtp_from'): 'vault@vault.test',
    };
    final s = load(smtp).smtp!;
    expect(
      (s.host, s.port, s.tls, s.user, s.password, s.from),
      ('smtp.test', 587, SmtpTls.starttls, null, null, 'vault@vault.test'),
    );
    expect(load({...smtp, env('smtp_tls'): 'implicit'}).smtp!.port, 465);
    expect(
      load({...smtp, env('smtp_tls'): 'none', env('smtp_port'): '25'})
          .smtp!
          .port,
      25,
    );
    expect(() => load({env('smtp_host'): 'smtp.test'}), errorOn('smtp_from'));
  });

  test('invalid values refuse to start, naming the key', () {
    final bad = <String, List<String>>{
      'database_url': [
        'mysql://x/y',
        'sqlite://',
        'sqlite:///',
        'postgres://h/db?sslmode=prefer',
        'postgres:///db',
        'postgres://h',
      ],
      'listen': ['8080', 'host:', ':8080', 'h:0', 'h:65536', 'h:http'],
      'public_url': [
        'vault.test',
        'ftp://vault.test',
        'http://vault.example.org',
        'https://',
        'https://u:p@vault.test',
        'https://vault.test/?q=1',
      ],
      'source_url': ['not a url', 'ftp://x.org'],
      'trusted_proxies': ['10.0.0.1', '10.0.0.0/33'],
      'log_level': ['trace', 'INFO'],
      'timezone': ['Mars/Olympus', ''],
      'setup_token': ['short', 'ABCDEFGHIJKLMNOPQRSTUVWXY1'],
      'min_client_version': ['1.0', '99.0.0'],
      'org_creation': ['admins'],
      'access_token_ttl': ['59s', '61m'],
      'refresh_token_ttl': ['23h', '366d'],
      'login_max_attempts': ['2', '101', 'ten'],
      'login_lockout': ['59s', '25h'],
      'invite_ttl': ['59m', '31d'],
      'max_orgs_per_user': ['-1', '10001'],
      'max_devices_per_user': ['10001'],
      'audit_retention_days': ['36501'],
      'audit_ip_retention_days': ['0', '36501'],
      'item_history_max_versions': ['36501'],
      'trash_retention_days': ['-1'],
      'smtp_port': ['0', '65536'],
      'smtp_tls': ['ssl'],
      'smtp_user': ['u' * 257],
      'smtp_password': ['p' * 257],
      'smtp_from': ['not-an-email'],
      'smtp_host': ['bad host'],
    };
    const smtp = {
      'UNFEUDAL_SMTP_HOST': 'smtp.test',
      'UNFEUDAL_SMTP_FROM': 'vault@vault.test',
    };
    for (final MapEntry(:key, value: values) in bad.entries) {
      for (final v in values) {
        expect(
          () => load({if (key.startsWith('smtp_')) ...smtp, env(key): v}),
          errorOn(key),
          reason: '$key=$v',
        );
      }
    }
  });
}
