// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/vault/org_writer.dart';
import 'package:unfeudal_client/src/vault/snippet_store.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../support/fakes.dart';
import '../support/org_fixtures.dart';

void main() {
  final key = SymmetricCipher.newKey();

  test('save, list sorted by name, search name, command and tags', () async {
    final store = SnippetStore(await testVault(key, LocalMirror.inMemory()));
    await store.save(
      SnippetMeta(
        name: 'restart nginx',
        command: 'sudo systemctl restart nginx',
        tags: ['web'],
      ),
    );
    await store.save(
      SnippetMeta(name: 'Disk', command: ' df -h\n', tags: ['ops']),
    );
    expect(store.list().map((e) => e.meta.name), ['Disk', 'restart nginx']);
    expect(store.list(query: 'SYSTEMCTL').single.meta.name, 'restart nginx');
    expect(store.list(query: 'ops').single.meta.command, ' df -h\n');
  });

  test(
    'edit keeps unknown fields and the folder; delete moves to the trash',
    () async {
      final v = await testVault(key, LocalMirror.inMemory());
      final folder = await v.saveFolder(FolderMeta.fromJson(folderJson('ops')));
      final id = await v.upsertItem(
        type: 'snippet',
        folderId: folder,
        meta: {
          'schemaVersion': 1,
          'name': 'a',
          'command': 'ls',
          'tags': <String>[],
          'color': 'ocre',
        },
      );
      final store = SnippetStore(v);
      final e = store.list().single;
      await store.save(
        SnippetMeta(
          name: 'b',
          command: e.meta.command,
          tags: e.meta.tags,
          extra: e.meta.extra,
        ),
        id: id,
      );
      expect(v.entry(id)!.meta!['color'], 'ocre');
      expect(v.entry(id)!.folderId, folder);
      await store.delete(id);
      expect(store.list(), isEmpty);
      expect(v.isTrashed(id), isTrue);
    },
  );

  test(
    'an invalid snippet is never offered; an oversized one is refused on save',
    () async {
      final v = await testVault(key, LocalMirror.inMemory());
      await v.upsertItem(
        type: 'snippet',
        meta: {
          'schemaVersion': 1,
          'name': ' ',
          'command': 'x',
          'tags': <String>[],
        },
      );
      final store = SnippetStore(v);
      expect(store.list(), isEmpty);
      await expectLater(
        store.save(SnippetMeta(name: 'big', command: 'x' * 16385, tags: [])),
        throwsFormatException,
      );
    },
  );

  test('org snippets: created in a folder, edited and trashed through the org writer', () async {
    final c = await ClientOrg.start();
    final f = newId();
    await c.keyring.put(f, FolderKeys.generate(1));
    final block = orgBlock(
      role: 'member',
      members: [c.me(role: 'member')],
      folderTree: [node(f)],
      acl: [
        aclRow(f, c.userId, allow: ['edit']),
      ],
    );
    final writer = OrgWriter(
      vault: c.vault,
      mirror: c.mirror,
      keyring: c.keyring,
      api: c.api,
      block: () => block,
      userId: c.userId,
      publicKey: c.publicKey,
      write: c.write,
      online: () => true,
      emit: c.events.add,
    );
    final store = SnippetStore(c.vault, writer: writer);
    final id = await store.save(
      SnippetMeta(name: 'deploy', command: 'make deploy'),
      target: OrgTarget(testOrgId, f),
    );
    Item queued() => c.mirror.outbox().singleWhere((e) => e.item.id == id).item;
    expect((queued().scope, queued().folderId), (ItemScope.org, f));
    await c.vault.reload();
    await store.save(
      SnippetMeta(name: 'deploy all', command: 'make all'),
      id: id,
    );
    expect(queued().scope, ItemScope.org);
    await c.vault.reload();
    expect(store.list().single.meta.name, 'deploy all');
    await store.delete(id);
    expect(queued().deleted, isTrue);
  });
}
