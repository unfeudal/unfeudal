// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  test('concrete aliases are hosts; the first value wins across matching blocks, globs and negation included', () {
    final r = parseSshConfig('''
# comment
Host bastion
  HostName 198.51.100.2
  Port 2222
  IdentityFile ~/.ssh/id_bastion
  IdentityFile ~/.ssh/ignored
Host db db-replica
  HostName %h.internal
  ProxyJump bastion
Host db*
  User postgres
Host * !bastion
  Port 2200
Host *
  User root
  Port 22
''');
    expect(
      [
        for (final h in r.hosts)
          (
            h.alias,
            h.hostName,
            h.port,
            h.user,
            h.identityFile,
            h.proxyJump?.join(','),
          ),
      ],
      [
        ('bastion', '198.51.100.2', 2222, 'root', '~/.ssh/id_bastion', null),
        ('db', 'db.internal', 2200, 'postgres', null, 'bastion'),
        (
          'db-replica',
          'db-replica.internal',
          2200,
          'postgres',
          null,
          'bastion',
        ),
      ],
    );
    expect(r.hosts.first.line, 2);
    expect(r.warnings, isEmpty);
  });

  test('directives before any Host apply to every host first', () {
    final h = parseSshConfig('User fallback\nHost a\n  User mine\n')
        .hosts
        .single;
    expect(h.user, 'fallback');
  });

  test('Key=Value, quotes and case-insensitive keywords', () {
    final h = parseSshConfig(
      'host box\n  HOSTNAME=10.0.0.9\n  user = "deploy"\n  identityfile "~/My Keys/id"\n',
    ).hosts.single;
    expect(
      (h.alias, h.hostName, h.user, h.identityFile),
      ('box', '10.0.0.9', 'deploy', '~/My Keys/id'),
    );
  });

  test('LocalForward becomes a port forward; ports below 1024 are allowed explicitly', () {
    final h = parseSshConfig(
      'Host web\n  LocalForward 8080 localhost:80\n  LocalForward 127.0.0.1:443 10.0.0.5:443\n',
    ).hosts.single;
    expect(
      [for (final f in h.forwards) f.toJson()],
      [
        {
          'localPort': 8080,
          'remoteHost': 'localhost',
          'remotePort': 80,
          'autoStart': false,
        },
        {
          'localPort': 443,
          'remoteHost': '10.0.0.5',
          'remotePort': 443,
          'autoStart': false,
          'allowLowPorts': true,
        },
      ],
    );
  });

  test('ProxyJump keeps the hop list; none clears it', () {
    final r = parseSshConfig(
      'Host a\n  ProxyJump none\nHost b\n  ProxyJump x,admin@y:2222\nHost *\n  ProxyJump z\n',
    );
    expect(
      [for (final h in r.hosts) h.proxyJump],
      [
        <String>[],
        ['x', 'admin@y:2222'],
      ],
    );
  });

  test('Include, Match, connection-changing options and bad values are warnings with their line', () {
    final r = parseSshConfig(
      'Include ~/.ssh/other\nHost a\n  Port 99999\n  ProxyCommand nc %h %p\n  DynamicForward 1080\n'
      'Match host a\n  User x\nHost b\n  LocalForward nope\n  ServerAliveInterval 30\n',
    );
    expect(
      [for (final w in r.warnings) (w.line, w.kind)],
      [
        (1, SshConfigWarningKind.include),
        (3, SshConfigWarningKind.badValue),
        (4, SshConfigWarningKind.unsupported),
        (5, SshConfigWarningKind.unsupported),
        (6, SshConfigWarningKind.match),
        (9, SshConfigWarningKind.badValue),
      ],
    );
    expect(
      [for (final h in r.hosts) (h.alias, h.port, h.user)],
      [('a', null, null), ('b', null, null)],
    );
  });

  test('empty or comment-only text gives nothing', () {
    final r = parseSshConfig('\n# only a comment\n');
    expect(r.hosts, isEmpty);
    expect(r.warnings, isEmpty);
  });
}
