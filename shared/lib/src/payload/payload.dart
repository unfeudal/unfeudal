// SPDX-License-Identifier: Apache-2.0

/// A decrypted `meta` or `secret`. Callers check `schemaVersion` on the raw
/// map before parsing, so a newer payload is shown read-only and never
/// rewritten.
abstract class Payload {
  const Payload({required this.schemaVersion, required this.extra});

  static const knownSchemaVersion = 1;

  final int schemaVersion;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson();
}

/// Maximum lengths in code points (strings) or entries (lists).
abstract final class PayloadLimits {
  static const name = 100;
  static const snippetName = 120;
  static const address = 253;
  static const remoteHost = 253;
  static const user = 64;
  static const tags = 32;
  static const tag = 64;
  static const notes = 10000;
  static const startupCommand = 4096;
  static const forwards = 32;
  static const sshKeyText = 16384;
  static const secretText = 1024;
  static const keyType = 64;
  static const displayName = 64;
  static const prefs = 64;
  static const command = 16384;
}
