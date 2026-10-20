// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:test/test.dart';
import 'package:unfeudal_server/src/orgs/org_access.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/matchers.dart';
import '../support/org_world.dart';
import '../support/test_server.dart';

void main() {
  late TestServer s;
  late OrgWorld w;
  setUp(() async {
    s = await TestServer.start(env: {'UNFEUDAL_MAX_ORGS_PER_USER': '1'});
    w = await OrgWorld.build(
      s,
      roles: {
        'adam': 'admin',
        'mia': 'member',
        'ana': 'member',
        'dis': 'owner',
      },
      accepted: {'ana'},
      teams: {
        'Ops': ['mia'],
      },
      folders: {'prod': null, 'db': 'prod', 'gone': null, 'bin': null},
    );
    await w.acl('prod', 'team:Ops', allow: ['view', 'connect']);
    await s.db.execute('UPDATE users SET disabled = 1 WHERE id = @u', {
      'u': w.id('dis'),
    });
    await s.db.execute('UPDATE items SET purged = 1 WHERE id = @f', {
      'f': w.folder('gone'),
    });
    await s.db.execute('UPDATE items SET deleted = 1 WHERE id = @f', {
      'f': w.folder('bin'),
    });
  });
  tearDown(() => s.close());

  Future<OrgSnapshot> snap() async =>
      (await s.db.transaction<OrgSnapshot?>((tx) => loadOrg(tx, w.orgId)))!;

  test(
    'loadOrg: the name and members with status, disabled and public key',
    () async {
      final o = await snap();
      expect(o.name, 'Acme');
      expect(o.members[w.id('ana')]!.status, MemberStatus.accepted);
      expect(
        (o.members[w.id('dis')]!.disabled, o.members[w.id('mia')]!.email),
        (true, 'mia@example.org'),
      );
      expect(o.members[w.id('mia')]!.publicKey, b64(w['mia'].bundle.publicKey));
    },
  );

  test('loadOrg: teams and ACL', () async {
    final o = await snap();
    expect(o.teams[w.teams['Ops']]!.memberIds, {w.id('mia')});
    expect(o.acl.single.allow, {Permission.view, Permission.connect});
  });

  test(
    'loadOrg: live folders (trashed in, purged out); unknown org null',
    () async {
      final o = await snap();
      expect(o.folders.keys.toSet(), {
        w.folder('prod'),
        w.folder('db'),
        w.folder('bin'),
      });
      expect(o.parentOf(w.folder('db')), w.folder('prod'));
      expect(await s.db.transaction((tx) => loadOrg(tx, newId())), isNull);
    },
  );

  test('permissionsOf: team ACL on the parent, admins all, accepted, disabled and outsiders nothing', () async {
    final o = await snap();
    expect(permissionsOf(o, w.id('mia'), w.folder('db')), {
      Permission.view,
      Permission.connect,
    });
    expect(
      permissionsOf(o, w.id('adam'), w.folder('db')),
      Permission.values.toSet(),
    );
    for (final who in [w.id('ana'), w.id('dis'), w.io.userId]) {
      expect(permissionsOf(o, who, w.folder('db')), isEmpty);
    }
    expect(
      permissionsOf(o, w.id('adam'), w.folder('gone')),
      isEmpty,
      reason: 'purged folder',
    );
    expect(o.viewable(w.id('mia')), {w.folder('prod'), w.folder('db')});
    expect(o.subtree(w.folder('prod')).toSet(), {
      w.folder('prod'),
      w.folder('db'),
    });
  });

  test('tree: viewable folders and their ancestors; without() drops a member everywhere', () async {
    await w.acl('db', 'user:ana', allow: ['view']);
    await s.db.execute(
      "UPDATE org_members SET status = 'confirmed' WHERE user_id = @u",
      {'u': w.id('ana')},
    );
    final o = await snap();
    expect(o.viewable(w.id('ana')), {w.folder('db')});
    expect(o.tree(w.id('ana')), {w.folder('db'), w.folder('prod')});
    final gone = o.without(w.id('mia'));
    expect(gone.members.containsKey(w.id('mia')), false);
    expect(gone.teams[w.teams['Ops']]!.memberIds, isEmpty);
    expect(gone.without(w.id('ana')).acl, hasLength(1));
  });

  test(
    'requireMember: 404 for strangers and unconfirmed, 403 for a missing role',
    () async {
      Future<MemberRow> call(
        String userId, {
        bool confirmed = true,
        bool admin = false,
        bool owner = false,
      }) => s.db.transaction(
        (tx) => requireMember(
          tx,
          w.orgId,
          userId,
          confirmed: confirmed,
          admin: admin,
          owner: owner,
        ),
      );
      expect((await call(w.id('mia'))).role, OrgRole.member);
      await expectLater(call(w.id('ana')), throwsApi(ApiErrorCode.notFound));
      expect(
        (await call(w.id('ana'), confirmed: false)).status,
        MemberStatus.accepted,
      );
      await expectLater(call(w.io.userId), throwsApi(ApiErrorCode.notFound));
      await expectLater(
        call(w.id('mia'), admin: true),
        throwsApi(ApiErrorCode.forbidden),
      );
      await expectLater(
        call(w.id('adam'), owner: true),
        throwsApi(ApiErrorCode.forbidden),
      );
      expect((await call(w.id('olivia'), owner: true)).role, OrgRole.owner);
    },
  );

  test(
    'lastOwnerOrgs and isLastOwner: confirmed, enabled owners only',
    () async {
      expect(
        await s.db.transaction((tx) => lastOwnerOrgs(tx, w.id('olivia'))),
        ['Acme'],
        reason: 'dis is disabled',
      );
      expect(isLastOwner(await snap(), w.id('olivia')), isTrue);
      await s.db.execute('UPDATE users SET disabled = 0 WHERE id = @u', {
        'u': w.id('dis'),
      });
      expect(
        await s.db.transaction((tx) => lastOwnerOrgs(tx, w.id('olivia'))),
        isEmpty,
      );
      expect(isLastOwner(await snap(), w.id('olivia')), isFalse);
      final e = lastOwnerError(['Beta', 'Acme']);
      expect(e.code, ApiErrorCode.conflict);
      expect(e.extra, {
        'reason': 'last_owner',
        'orgs': ['Acme', 'Beta'],
      });
    },
  );

  test(
    'currentKeyVersion: history version, else MAX(folder_keys.version), else 0',
    () async {
      final f = w.folder('prod');
      Future<int> current() =>
          s.db.transaction((tx) => currentKeyVersion(tx, f));
      expect(await current(), 0);
      await w.keys('prod', 2, ['mia']);
      expect(await current(), 2);
      await s.db.execute(
        "INSERT INTO folder_key_history (org_id, folder_id, version, body) VALUES (@o, @f, 3, '{}')",
        {'o': w.orgId, 'f': f},
      );
      expect(await current(), 3);
    },
  );

  test(
    'bumpOrgSeq adds one; checkMembershipCap refuses at max_orgs_per_user',
    () async {
      final before = await w.orgSeq();
      await s.db.transaction(bumpOrgSeq);
      expect(await w.orgSeq(), before + 1);
      await expectLater(
        s.db.transaction(
          (tx) => checkMembershipCap(tx, s.deps.config, w.id('mia')),
        ),
        throwsApi(ApiErrorCode.forbidden),
      );
      await s.db.transaction(
        (tx) => checkMembershipCap(tx, s.deps.config, w.io.userId),
      );
    },
  );
}
