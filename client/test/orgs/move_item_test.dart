// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/vault/vault.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';
import '../support/sync_harness.dart';

void main() {
  late AppState s;
  late String outer, inner, web;
  VaultEntry entry(String id) => s.vault!.entry(id)!;

  setUp(() async {
    final h = SyncHarness();
    await h.createAccount(testEmail, testPassword);
    s = testAppState(harness: h);
    await s.boot();
    await s.login(server: h.baseUrl, email: testEmail, password: testPassword);
    final vault = s.vault!;
    outer = await vault.upsertItem(type: 'folder', meta: folderJson('Outer'));
    inner = await vault.upsertItem(
      type: 'folder',
      folderId: outer,
      meta: folderJson('Inner'),
    );
    web = await vault.upsertItem(type: 'host', meta: hostJson('web'));
  });

  test('a host moves into a folder and back to the root', () async {
    await s.orgs!.moveItem(entry(web), inner);
    expect(entry(web).folderId, inner);
    await s.orgs!.moveItem(entry(web), null);
    expect(entry(web).folderId, isNull);
  });

  test('a folder never moves into itself or below it', () {
    expect(s.orgs!.canMove(entry(outer), outer), isFalse);
    expect(s.orgs!.canMove(entry(outer), inner), isFalse);
    expect(s.orgs!.canMove(entry(inner), null), isTrue);
  });

  test('an item does not move to where it already is', () {
    expect(s.orgs!.canMove(entry(web), null), isFalse);
    expect(s.orgs!.canMove(entry(inner), outer), isFalse);
  });

  test('a folder moves with its name and defaults kept', () async {
    await s.orgs!.moveItem(entry(inner), null);
    expect(entry(inner).folderId, isNull);
    expect(entry(inner).name, 'Inner');
  });
}
