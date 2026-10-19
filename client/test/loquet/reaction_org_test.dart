// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/src/events/app_events.dart';
import 'package:unfeudal_client/src/loquet/line_bank.dart';
import 'package:unfeudal_client/src/loquet/loquet_memory.dart';
import 'package:unfeudal_client/src/loquet/reaction_engine.dart';

void main() {
  test(
    'first shared vault and first key rotation are milestones, once ever',
    () {
      final e = ReactionEngine(
        memory: LoquetMemory(),
        now: () => DateTime(2026, 10, 15, 12),
      );
      final shared = e.handle(const SharedVaultCreated());
      expect((shared!.line, shared.important), (LineKey.sharedVault, true));
      expect(e.handle(const SharedVaultCreated()), isNull);
      expect(e.handle(const KeyRotated())!.line, LineKey.firstKeyRotation);
      expect(e.handle(const KeyRotated()), isNull);
    },
  );
}
