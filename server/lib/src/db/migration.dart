// SPDX-License-Identifier: AGPL-3.0-or-later
import 'db.dart';

class Migration {
  const Migration(this.version, this.statements, {this.backfill});
  final int version;
  final List<String> statements;

  /// Fills what the statements created from existing rows, in the same transaction; for data SQL cannot
  /// move the same way on both engines.
  final Future<void> Function(Tx tx)? backfill;
}
