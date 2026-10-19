// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/config/config.dart';
import 'package:unfeudal_server/src/config/features.dart';

const base = {'UNFEUDAL_PUBLIC_URL': 'https://vault.test'};
Config load(Map<String, String> env, [String? yaml]) =>
    Config.load({...base, ...env}, yamlText: yaml);
Matcher errorOn(String key) =>
    throwsA(isA<ConfigError>().having((e) => e.key, 'key', key));

void main() {
  test('every key is listed once', () {
    expect(Config.keys, hasLength(30));
    expect(Config.keys.toSet(), hasLength(30));
    expect(
      Config.keys,
      containsAll([
        'database_url',
        'public_url',
        'trash_retention_days',
        'smtp_from',
      ]),
    );
  });

  test(
    'broken YAML refuses to start, names the file, never echoes its text',
    () {
      for (final yaml in [
        'smtp_password: s3cret-value\nsmtp_host: [unclosed',
        'smtp_password: s3cret-value\nsmtp_password: other-value',
      ]) {
        expect(
          () => load(const {}, yaml),
          throwsA(
            isA<ConfigError>()
                .having((e) => e.key, 'key', 'UNFEUDAL_CONFIG_FILE')
                .having((e) => '$e', 'text', isNot(contains('value'))),
          ),
        );
      }
    },
  );

  test('public_url is required', () {
    expect(() => Config.load(const {}), errorOn('public_url'));
  });

  test('env wins over YAML; YAML scalars and lists are read', () {
    const yaml =
        'log_level: debug\nlogin_max_attempts: 20\ntrusted_proxies: [10.0.0.0/8, "fd00::/8"]\nmax_vault_size: 0\n';
    final c = load({'UNFEUDAL_LOG_LEVEL': 'warn'}, yaml);
    expect(
      (c.loginMaxAttempts, c.trustedProxies.length, c.maxVaultSize),
      (20, 2, 0),
    );
    expect(c.logLevel.name, 'warn');
    expect(
      load({'UNFEUDAL_TRUSTED_PROXIES': '10.0.0.0/8, 192.168.0.0/16'})
          .trustedProxies,
      hasLength(2),
    );
    expect(
      load(const {}, 'setup_token:\n').setupToken,
      isNull,
      reason: 'YAML null = unset',
    );
  });

  test('unknown keys, variables and flags refuse to start, naming them', () {
    expect(() => load(const {}, 'colour: blue\n'), errorOn('colour'));
    expect(() => load({'UNFEUDAL_COLOUR': 'blue'}), errorOn('UNFEUDAL_COLOUR'));
    expect(
      () => load(const {}, 'features:\n  telemetry: true\n'),
      errorOn('features.telemetry'),
    );
    expect(
      () => load({'UNFEUDAL_FEATURE_TELEMETRY': 'true'}),
      errorOn('UNFEUDAL_FEATURE_TELEMETRY'),
    );
    expect(() => load(const {}, '- a\n- b\n'), errorOn('UNFEUDAL_CONFIG_FILE'));
    expect(() => load(const {}, 'log_level: [a]\n'), errorOn('log_level'));
    expect(
      load({'UNFEUDAL_CONFIG_FILE': '/etc/unfeudal.yaml', 'PATH': '/bin'})
          .publicUrl
          .host,
      'vault.test',
    );
  });

  test('flags from YAML and env, env wins; only true and false', () {
    final c = load({
      'UNFEUDAL_FEATURE_ORGS': 'false',
    }, 'features:\n  orgs: true\n  mascot: false\n');
    expect(
      (c.features.enabled(Flag.orgs), c.features.enabled(Flag.mascot)),
      (false, false),
    );
    expect(
      () => load({'UNFEUDAL_FEATURE_ORGS': 'yes'}),
      errorOn('UNFEUDAL_FEATURE_ORGS'),
    );
    expect(
      () => load(const {}, 'features:\n  orgs: "no"\n'),
      errorOn('features.orgs'),
    );
  });

  test('durations, sizes and counts follow the config grammar', () {
    final c = load({
      'UNFEUDAL_ACCESS_TOKEN_TTL': '1h',
      'UNFEUDAL_REFRESH_TOKEN_TTL': '1d',
      'UNFEUDAL_LOGIN_LOCKOUT': '90s',
      'UNFEUDAL_MAX_VAULT_SIZE': '512KB',
      'UNFEUDAL_MAX_ORG_SIZE': '1GB',
    });
    expect(
      (c.accessTokenTtl, c.refreshTokenTtl, c.loginLockout),
      (
        const Duration(hours: 1),
        const Duration(days: 1),
        const Duration(seconds: 90),
      ),
    );
    expect((c.maxVaultSize, c.maxOrgSize), (512 * 1024, 1 << 30));
    for (final bad in ['15', '15 m', '-1m', '1w', '1.5h', 'm']) {
      expect(
        () => load({'UNFEUDAL_ACCESS_TOKEN_TTL': bad}),
        errorOn('access_token_ttl'),
        reason: bad,
      );
    }
    for (final bad in ['50', '50mb', '1TB', '-1MB', '0MB ']) {
      expect(
        () => load({'UNFEUDAL_MAX_VAULT_SIZE': bad}),
        errorOn('max_vault_size'),
        reason: bad,
      );
    }
  });

  test('a bad secret value is never echoed', () {
    for (final (key, env) in [
      ('setup_token', 'UNFEUDAL_SETUP_TOKEN'),
      ('smtp_password', 'UNFEUDAL_SMTP_PASSWORD'),
    ]) {
      final secret = 'leakme${'z' * 300}';
      try {
        load({env: secret});
        fail('accepted $key');
      } on ConfigError catch (e) {
        expect(e.key, key);
        expect('$e${e.message}', isNot(contains('leakme')));
      }
    }
  });
}
