// SPDX-License-Identifier: Apache-2.0

/// Plain `X.Y.Z`: no prefix, pre-release or build suffix.
class Version implements Comparable<Version> {
  const Version(this.major, this.minor, this.patch);

  static Version parse(String s) {
    final match = s.length <= 32 ? _pattern.firstMatch(s) : null;
    if (match == null) throw FormatException('invalid version', s);
    // int.parse throws FormatException on overflow.
    return Version(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  static final _pattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(Version other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

int compareVersions(String a, String b) =>
    Version.parse(a).compareTo(Version.parse(b));
