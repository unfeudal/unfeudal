// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/import/ssh_config_import.dart';
import 'package:unfeudal_client/src/keys/key_tools.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/vault/vault.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';

void main() {
  late Vault v;
  late Map<String, String> files;
  setUp(() async {
    v = await testVault(SymmetricCipher.newKey(), LocalMirror.inMemory());
    files = {};
  });
  SshConfigImporter importer() =>
      SshConfigImporter(v, home: '/home/c', readFile: (p) async => files[p]);

  test('plan: hosts, keys from IdentityFile, duplicates flagged, an unreadable key warned', () async {
    files['/home/c/.ssh/id_ed25519'] = (await generateEd25519(
      comment: 'c@laptop',
    )).privateKeyPem;
    await v.upsertItem(type: 'host', meta: hostJson('old'));
    final plan = await importer().plan(
      'Host bastion\n  HostName 198.51.100.2\n  IdentityFile ~/.ssh/id_ed25519\n'
      'Host db\n  IdentityFile ~/.ssh/missing\nHost old\n',
    );
    expect(
      [for (final h in plan.hosts) (h.source.alias, h.duplicate)],
      [('bastion', false), ('db', false), ('old', true)],
    );
    expect(plan.keys.single.path, '/home/c/.ssh/id_ed25519');
    expect(plan.keys.single.publicKey, startsWith('ssh-ed25519 '));
    expect(
      [for (final w in plan.warnings) (w.line, w.kind)],
      [(4, SshConfigWarningKind.keyUnreadable)],
    );
  });

  test('apply: identity with kind, public key and passphrase; host linked to it, to its jump host, with its forward', () async {
    files['/home/c/.ssh/k'] = (await generateEd25519(passphrase: 'pp'))
        .privateKeyPem;
    final i = importer();
    final plan = await i.plan(
      'Host target\n  HostName 10.0.1.10\n  User deploy\n  ProxyJump bastion\n'
      '  IdentityFile ~/.ssh/k\n  LocalForward 5432 localhost:5432\nHost bastion\n  HostName 198.51.100.2\n',
    );
    expect(plan.keys.single.needsPassphrase, isTrue);
    expect(
      await i.apply(
        plan,
        aliases: {'target', 'bastion'},
        passphrases: {'/home/c/.ssh/k': 'pp'},
      ),
      2,
    );
    final hosts = {for (final e in v.ofKind(ItemKind.host)) e.name: e};
    final target = HostMeta.fromJson(hosts['target']!.meta);
    expect(
      (
        target.address,
        target.user,
        target.jumpHostId,
        target.forwards.single.localPort,
      ),
      ('10.0.1.10', 'deploy', hosts['bastion']!.id, 5432),
    );
    final ident = v.ofKind(ItemKind.identity).single;
    expect(target.identityId, ident.id);
    expect(ident.meta!['kind'], 'privateKey');
    expect(ident.meta!['publicKey'], startsWith('ssh-ed25519 '));
    expect((await v.identitySecret(ident.id))!.passphrase, 'pp');
  });

  test('a wrong passphrase skips the key with a warning; the host comes without it', () async {
    files['/home/c/.ssh/k'] = (await generateEd25519(passphrase: 'pp'))
        .privateKeyPem;
    final i = importer();
    final plan = await i.plan('Host a\n  IdentityFile ~/.ssh/k\n');
    expect(
      await i.apply(
        plan,
        aliases: {'a'},
        passphrases: {'/home/c/.ssh/k': 'nope'},
      ),
      1,
    );
    expect(v.ofKind(ItemKind.identity), isEmpty);
    expect(
      HostMeta.fromJson(v.ofKind(ItemKind.host).single.meta).identityId,
      isNull,
    );
    expect(
      plan.warnings.map((w) => w.kind),
      contains(SshConfigWarningKind.keyUnreadable),
    );
  });

  test('ProxyJump: unknown alias or user@host dropped, loop dropped, chains set hop by hop', () async {
    final plan = await importer().plan(
      'Host a\n  ProxyJump b\nHost b\n  ProxyJump a\nHost c\n  ProxyJump admin@gw:2222\n'
      'Host d\n  ProxyJump e,f\nHost e\nHost f\n',
    );
    expect(
      plan.warnings.map((w) => w.kind),
      unorderedEquals([
        SshConfigWarningKind.jumpUnresolved,
        SshConfigWarningKind.jumpLoop,
      ]),
    );
    expect(
      {for (final h in plan.hosts) h.source.alias: h.jumpAlias},
      {'a': null, 'b': 'a', 'c': null, 'd': 'f', 'e': null, 'f': 'e'},
    );
  });

  test('a host over the item limits is warned and left out', () async {
    final plan = await importer().plan('Host ${'x' * 101}\nHost ok\n');
    expect(plan.hosts.map((h) => h.source.alias), ['ok']);
    expect(plan.warnings.single.kind, SshConfigWarningKind.badValue);
  });
}
