// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:unfeudal_tool/release.dart';

/// `bump.dart <server|client> <patch|minor|major|X.Y.Z>`, run from `tool/`; stdout is `$GITHUB_OUTPUT` lines.
void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'usage: bump.dart <server|client> <patch|minor|major|X.Y.Z>',
    );
    exit(64);
  }
  final [package, level] = args;
  final version = bump(
    Directory('..'),
    package,
    level,
    date: DateTime.now().toUtc(),
  );
  stdout
    ..writeln('version=$version')
    ..writeln('title=chore(release): $package $version');
}
