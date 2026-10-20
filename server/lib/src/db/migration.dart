// SPDX-License-Identifier: AGPL-3.0-or-later
class Migration {
  const Migration(this.version, this.statements);
  final int version;
  final List<String> statements;
}
