// SPDX-License-Identifier: AGPL-3.0-or-later
import 'migration.dart';
import 'migrations/m0001_core.dart';
import 'migrations/m0002_orgs.dart';
import 'migrations/m0003_audit.dart';
import 'migrations/m0004_locale.dart';
import 'migrations/m0005_audit_targets.dart';

/// Server schema, one file per migration under `migrations/`, one statement
/// per string. A released migration is never edited: a change is a new file,
/// named after what it does (`m0005_add_<column>_to_<table>.dart`).
const migrations = <Migration>[
  coreMigration,
  orgsMigration,
  auditMigration,
  localeMigration,
  auditTargetsMigration,
];
