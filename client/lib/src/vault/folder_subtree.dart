// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import 'vault.dart';

/// [folderId] and every folder below it: never a valid parent for that folder.
Set<String> folderSubtree(Vault vault, String folderId) {
  final out = {folderId};
  for (var grew = true; grew;) {
    grew = false;
    for (final e in vault.ofKind(ItemKind.folder)) {
      if (out.contains(e.folderId) && out.add(e.id)) grew = true;
    }
  }
  return out;
}
