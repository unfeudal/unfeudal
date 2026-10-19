// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:unfeudal_tool/checks.dart';

/// `changelog.dart <server|client> <X.Y.Z>`, run from `tool/`: prints the release notes of that version.
void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: changelog.dart <server|client> <X.Y.Z>');
    exit(64);
  }
  final [package, version] = args;
  final notes = changelogSection(
    File('../$package/CHANGELOG.md').readAsStringSync(),
    version,
  );
  if (notes == null) {
    stderr.writeln('$package/CHANGELOG.md has no [$version] section');
    exit(1);
  }
  stdout.writeln(notes);
}
