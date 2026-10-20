// SPDX-License-Identifier: Apache-2.0
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart' show constantTimeBytesEquality;

final _random = Random.secure();

Uint8List secureBytes(int n) =>
    Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

/// Compares in time independent of where the bytes differ; use it for MACs, hashes and keys.
bool constantTimeEquals(List<int> a, List<int> b) =>
    constantTimeBytesEquality.equals(a, b);

/// The 32-byte SHA-256 digest of [bytes].
Future<Uint8List> sha256Digest(List<int> bytes) async =>
    Uint8List.fromList((await Sha256().hash(bytes)).bytes);
