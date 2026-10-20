// SPDX-License-Identifier: Apache-2.0
import 'package:path/path.dart' as p;
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../keys/key_tools.dart';
import '../vault/vault.dart';

class PlannedHost {
  const PlannedHost({
    required this.source,
    required this.duplicate,
    required this.keyPath,
    required this.jumpAlias,
  });

  final SshConfigHost source;

  /// A personal host with the same name (case-insensitive) is already in the vault.
  final bool duplicate;

  /// `IdentityFile` expanded; null when unset or unreadable.
  final String? keyPath;
  final String? jumpAlias;
}

class PlannedKey {
  const PlannedKey(this.path, this.pem, this.publicKey);

  final String path;
  final String pem;

  /// Null until the passphrase is known.
  final String? publicKey;
  bool get needsPassphrase => publicKey == null;
}

class ImportPlan {
  const ImportPlan(this.hosts, this.keys, this.warnings);

  final List<PlannedHost> hosts;
  final List<PlannedKey> keys;

  /// Growable: [SshConfigImporter.apply] adds the keys it could not open.
  final List<SshConfigWarning> warnings;
}

/// Turns a `~/.ssh/config` into personal hosts and identities: [plan] previews, [apply] writes the chosen hosts.
class SshConfigImporter {
  SshConfigImporter(this.vault, {required this.readFile, required this.home});

  final Vault vault;
  final Future<String?> Function(String path) readFile;
  final String home;

  Future<ImportPlan> plan(String configText) async {
    final parsed = parseSshConfig(configText);
    final warnings = [...parsed.warnings];
    final valid = <SshConfigHost>[];
    for (final h in parsed.hosts) {
      try {
        HostMeta.fromJson(_meta(h).toJson());
        valid.add(h);
      } on FormatException {
        warnings.add(
          SshConfigWarning(h.line, SshConfigWarningKind.badValue, h.alias),
        );
      }
    }
    final existing = {
      for (final e in vault.ofKind(ItemKind.host))
        if (e.orgId == null) e.name?.toLowerCase(),
    };
    final keys = <String, PlannedKey?>{};
    for (final h in valid) {
      final path = _expand(h.identityFile);
      if (path == null || keys.containsKey(path)) continue;
      keys[path] = await _readKey(path);
      if (keys[path] == null) {
        warnings.add(
          SshConfigWarning(h.line, SshConfigWarningKind.keyUnreadable, path),
        );
      }
    }
    final jumps = _jumps(valid, warnings);
    return ImportPlan(
      [
        for (final h in valid)
          PlannedHost(
            source: h,
            duplicate: existing.contains(h.alias.toLowerCase()),
            keyPath: keys[_expand(h.identityFile)]?.path,
            jumpAlias: jumps[h.alias],
          ),
      ],
      [...keys.values.nonNulls],
      warnings,
    );
  }

  /// Writes the hosts named in [aliases] and the keys they use; returns the number of hosts written.
  Future<int> apply(
    ImportPlan plan, {
    required Set<String> aliases,
    Map<String, String> passphrases = const {},
    String? folderId,
  }) async {
    final chosen = [
      for (final h in plan.hosts)
        if (aliases.contains(h.source.alias)) h,
    ];
    // ids first, so a jump link resolves whatever the order; a jump to a host not chosen is dropped
    final ids = {for (final h in chosen) h.source.alias: newId()};
    final identities = <String, String?>{};
    for (final h in chosen) {
      final path = h.keyPath;
      if (path == null || identities.containsKey(path)) continue;
      final key = plan.keys.firstWhere((k) => k.path == path);
      identities[path] = await _writeIdentity(key, passphrases[path]);
      if (identities[path] == null) {
        plan.warnings.add(
          SshConfigWarning(
            h.source.line,
            SshConfigWarningKind.keyUnreadable,
            path,
          ),
        );
      }
    }
    for (final h in chosen) {
      await vault.upsertItem(
        id: ids[h.source.alias],
        type: 'host',
        folderId: folderId,
        meta: _meta(
          h.source,
          identityId: identities[h.keyPath],
          jumpHostId: ids[h.jumpAlias],
        ).toJson(),
      );
    }
    return chosen.length;
  }

  HostMeta _meta(SshConfigHost h, {String? identityId, String? jumpHostId}) =>
      HostMeta(
        name: h.alias,
        address: h.hostName ?? h.alias,
        port: h.port,
        user: h.user,
        identityId: identityId,
        forwards: h.forwards,
        jumpHostId: jumpHostId,
      );

  String? _expand(String? path) => path == null
      ? null
      : path.startsWith('~/')
      ? '$home/${path.substring(2)}'
      : path;

  Future<PlannedKey?> _readKey(String path) async {
    final pem = await readFile(path);
    if (pem == null) return null;
    try {
      return PlannedKey(path, pem, publicKeyOf(pem));
    } on InvalidKey {
      return PlannedKey(path, pem, null);
    }
  }

  // The identity's id; null when the key does not open with passphrase.
  Future<String?> _writeIdentity(PlannedKey key, String? passphrase) async {
    final String publicKey;
    try {
      publicKey = key.publicKey ?? publicKeyOf(key.pem, passphrase: passphrase);
    } on InvalidKey {
      return null;
    }
    return vault.upsertItem(
      type: 'identity',
      meta: IdentityMeta(
        name: p.basename(key.path),
        kind: IdentityKind.privateKey,
        publicKey: publicKey,
      ).toJson(),
      secret: IdentitySecret(
        kind: IdentityKind.privateKey,
        privateKeyPem: key.pem,
        passphrase: key.needsPassphrase ? passphrase : null,
      ).toJson(),
    );
  }

  Map<String, String?> _jumps(
    List<SshConfigHost> hosts,
    List<SshConfigWarning> warnings,
  ) {
    final byAlias = {for (final h in hosts) h.alias: h};
    final jump = <String, String?>{for (final h in hosts) h.alias: null};
    for (final h in hosts) {
      final hops = h.proxyJump ?? const <String>[];
      if (hops.isEmpty) continue;
      if (hops.any((a) => !byAlias.containsKey(a))) {
        // user@host:port or an alias not in the file
        warnings.add(
          SshConfigWarning(
            h.line,
            SshConfigWarningKind.jumpUnresolved,
            hops.join(','),
          ),
        );
        continue;
      }
      jump[h.alias] = hops.last;
    }
    for (final h in hosts) {
      // ProxyJump a,b: b is reached through a, unless b has its own jump host
      final hops = h.proxyJump ?? const <String>[];
      if (hops.length < 2 || jump[h.alias] == null) continue;
      for (var i = 1; i < hops.length; i++) {
        jump[hops[i]] ??= hops[i - 1];
        if (jump[hops[i]] != hops[i - 1]) {
          warnings.add(
            SshConfigWarning(
              h.line,
              SshConfigWarningKind.jumpUnresolved,
              hops.join(','),
            ),
          );
          jump[h.alias] = null;
          break;
        }
      }
    }
    for (final h in hosts) {
      try {
        resolveJumpChain(
          h.alias,
          (id) => byAlias.containsKey(id)
              ? ResolvedHost(port: 22, jumpHostId: jump[id], sources: const {})
              : null,
        );
      } on Exception {
        // JumpLoop, JumpTooDeep: this host's jump is dropped, the hosts it points to keep theirs
        warnings.add(
          SshConfigWarning(h.line, SshConfigWarningKind.jumpLoop, h.alias),
        );
        jump[h.alias] = null;
      }
    }
    return jump;
  }
}
