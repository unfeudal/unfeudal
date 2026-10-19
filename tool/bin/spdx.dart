// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:unfeudal_tool/checks.dart';

/// `spdx.dart [root]` (default `..`): exit 1 with each source missing its SPDX header on stderr.
void main(List<String> args) {
  final problems = spdxProblems(
    Directory(args.isEmpty ? '..' : args.single).absolute,
  );
  for (final path in problems) {
    stderr.writeln('$path: missing SPDX header');
  }
  exit(problems.isEmpty ? 0 : 1);
}
