// SPDX-License-Identifier: Apache-2.0
import 'dart:io';

import 'package:unfeudal_tool/release.dart';

/// `check_tag.dart <tag>`, run from `tool/`: exit 1 with each problem on stderr when the tree does not match the tag.
void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: check_tag.dart <server-vX.Y.Z|client-vX.Y.Z>');
    exit(64);
  }
  final problems = checkTag(Directory('..'), args.single);
  problems.forEach(stderr.writeln);
  exit(problems.isEmpty ? 0 : 1);
}
