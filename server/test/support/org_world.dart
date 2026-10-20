// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'items.dart';
import 'test_server.dart';

/// One org "Acme". `olivia` is its confirmed owner; every name in [roles] is an account `<name>@example.org`
/// with that role (confirmed unless in [accepted]). [folders]: name to parent name (null = root), created in map
/// order by olivia through `PUT /items`. [teams]: name to member names. `io` is the Instance Owner, not a member.
class OrgWorld {
  OrgWorld._(this.s, this.io, this.orgId, this.users, this.teams, this.folders);
  final TestServer s;
  final TestSession io;
  final String orgId;
  final Map<String, TestSession> users;
  final Map<String, String> teams;
  final Map<String, String> folders;

  TestSession operator [](String name) => users[name]!;
  String id(String name) => users[name]!.userId;
  String folder(String name) => folders[name]!;

  static Future<OrgWorld> build(
    TestServer s, {
    Map<String, String> roles = const {},
    Set<String> accepted = const {},
    Map<String, List<String>> teams = const {},
    Map<String, String?> folders = const {},
  }) async {
    final io = await s.setupOwner();
    final orgId = newId();
    await s.db.execute(
      'INSERT INTO orgs (id, name, settings, created_at) VALUES (@o, @n, @st, @t)',
      {'o': orgId, 'n': 'Acme', 'st': '{}', 't': iso(s.clock.now())},
    );
    final users = <String, TestSession>{};
    for (final MapEntry(key: name, value: role) in {
      'olivia': 'owner',
      ...roles,
    }.entries) {
      users[name] = await s.createUser('$name@example.org');
      await s.db.execute(
        'INSERT INTO org_members (org_id, user_id, role, status) VALUES (@o, @u, @r, @st)',
        {
          'o': orgId,
          'u': users[name]!.userId,
          'r': role,
          'st': accepted.contains(name) ? 'accepted' : 'confirmed',
        },
      );
    }
    final teamIds = <String, String>{};
    for (final MapEntry(key: name, value: members) in teams.entries) {
      final id = teamIds[name] = newId();
      await s.db.execute(
        'INSERT INTO teams (id, org_id, name) VALUES (@id, @o, @n)',
        {'id': id, 'o': orgId, 'n': name},
      );
      for (final m in members) {
        await s.db.execute(
          'INSERT INTO team_members (org_id, team_id, user_id) VALUES (@o, @t, @u)',
          {'o': orgId, 't': id, 'u': users[m]!.userId},
        );
      }
    }
    final world = OrgWorld._(s, io, orgId, users, teamIds, {});
    for (final MapEntry(key: name, value: parent) in folders.entries) {
      final item = await testItem(
        users['olivia']!,
        type: 'folder',
        scope: 'org',
        orgId: orgId,
        folderId: parent == null ? null : world.folders[parent],
        meta: {'name': name},
      );
      final r = await world.put(users['olivia']!, item, 0);
      if (r.status != 200) {
        throw StateError('folder $name: ${r.status} ${r.json}');
      }
      world.folders[name] = item['id']! as String;
    }
    return world;
  }

  Future<TestResponse> put(
    TestSession who,
    Map<String, Object?> item,
    int ifMatch,
  ) => s.put(
    '/api/v1/items/${item['id']}',
    token: who.accessToken,
    body: item,
    headers: {'if-match': '$ifMatch'},
  );

  /// An org item body in [folder] (for a folder item, [folder] is its parent).
  Future<Map<String, Object?>> item(
    TestSession who, {
    String? id,
    String type = 'host',
    String? folder,
    int keyVersion = 1,
    bool secret = false,
    bool deleted = false,
  }) => testItem(
    who,
    id: id,
    type: type,
    scope: 'org',
    orgId: orgId,
    folderId: folder == null ? null : folders[folder],
    keyVersion: keyVersion,
    secret: secret,
    deleted: deleted,
  );

  /// Direct ACL row; [principal] is `user:<name>` or `team:<name>`.
  Future<void> acl(
    String folder,
    String principal, {
    List<String> allow = const [],
    List<String> deny = const [],
  }) async {
    final [type, name] = principal.split(':');
    await s.db.execute(
      'INSERT INTO acl_entries (org_id, folder_id, principal_type, principal_id, allow, deny) VALUES (@o, @f, @t, @p, @a, @d)',
      {
        'o': orgId,
        'f': folders[folder],
        't': type,
        'p': type == 'team' ? teams[name] : users[name]!.userId,
        'a': jsonEncode(allow),
        'd': jsonEncode(deny),
      },
    );
  }

  /// Direct key rows at [version] for [names]; names in [metaOnly] get no secret wrap.
  Future<void> keys(
    String folder,
    int version,
    List<String> names, {
    Set<String> metaOnly = const {},
  }) async {
    for (final n in names) {
      await s.db.execute(
        'INSERT INTO folder_keys (org_id, folder_id, user_id, version, meta_wrapped, secret_wrapped) '
        'VALUES (@o, @f, @u, @v, @m, @sec) '
        'ON CONFLICT (folder_id, user_id) DO UPDATE SET version = @v, meta_wrapped = @m, secret_wrapped = @sec',
        {
          'o': orgId,
          'f': folders[folder],
          'u': users[n]!.userId,
          'v': version,
          'm': jsonEncode(sealed(folders[folder]!, version, 'meta')),
          'sec': metaOnly.contains(n)
              ? null
              : jsonEncode(sealed(folders[folder]!, version, 'secret')),
        },
      );
    }
  }

  /// A wrap entry of `PUT /folders/{f}/keys` (the server checks labels only, it never opens a box).
  Map<String, Object?> wrap(
    String name,
    String folder,
    int version, {
    bool secret = true,
  }) => {
    'userId': users[name]!.userId,
    'version': version,
    'meta': sealed(folders[folder]!, version, 'meta'),
    'secret': secret ? sealed(folders[folder]!, version, 'secret') : null,
  };

  Map<String, Object?> history(String folder, int version) => {
    'version': version,
    'meta': Envelope(
      v: 1,
      alg: Envelope.xchacha,
      keyId: KeyIds.folder(folders[folder]!, version, PayloadPart.meta),
      nonce: _bytes(24),
      ct: _bytes(48),
    ).toJson(),
    'secret': null,
  };

  static Map<String, Object?> sealed(
    String folderId,
    int version,
    String part,
  ) => Envelope(
    v: 1,
    alg: Envelope.xchacha,
    keyId: 'sealed:folder:$folderId:v$version:$part',
    nonce: _bytes(24),
    ct: _bytes(48),
  ).toJson();

  static Uint8List _bytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => Random.secure().nextInt(256)));

  Future<SyncPage> sync(
    TestSession who, {
    int cursor = 0,
    int orgCursor = 0,
  }) async {
    final r = await s.get(
      '/api/v1/sync?cursor=$cursor&orgCursor=$orgCursor',
      token: who.accessToken,
    );
    if (r.status != 200) throw StateError('sync: ${r.status} ${r.json}');
    return SyncPage.fromJson(r.json);
  }

  Future<OrgBlock> block(TestSession who) async => (await sync(who)).org!;

  Future<int> orgSeq() async =>
      (await s.db.query("SELECT value FROM counters WHERE name = 'org_seq'"))
              .single['value']!
          as int;

  Future<int> count(
    String table, [
    String where = '1 = 1',
    Map<String, Object?> p = const {},
  ]) async =>
      (await s.db.query(
            'SELECT count(*) AS n FROM $table WHERE $where',
            p,
          )).single['n']!
          as int;
}
