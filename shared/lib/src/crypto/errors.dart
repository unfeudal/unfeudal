// SPDX-License-Identifier: Apache-2.0

final class WrongPassword implements Exception {
  const WrongPassword();
}

final class DecryptionFailed implements Exception {
  const DecryptionFailed();
}

final class UnsupportedEnvelope implements Exception {
  const UnsupportedEnvelope(this.what);

  final String what;

  @override
  String toString() =>
      'UnsupportedEnvelope: $what is not supported by this version. '
      'Update Unfeudal to open it.';
}

final class UnsupportedKdf implements Exception {
  const UnsupportedKdf(this.alg);

  final String alg;

  @override
  String toString() =>
      'UnsupportedKdf: $alg is not supported by this version. '
      'Update Unfeudal to open it.';
}

final class WeakKdf implements Exception {
  const WeakKdf();
}

final class WeakPassword implements Exception {
  const WeakPassword();
}

final class InvalidRecoveryKey implements Exception {
  const InvalidRecoveryKey();
}

final class KeyLabelMismatch implements Exception {
  const KeyLabelMismatch(this.label);

  final String label;

  @override
  String toString() => 'KeyLabelMismatch: $label';
}
