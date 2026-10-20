// SPDX-License-Identifier: AGPL-3.0-or-later
import '../migration.dart';

const localeMigration = Migration(4, [
  r"""ALTER TABLE users ADD COLUMN locale TEXT NOT NULL DEFAULT 'en'""",
]);
