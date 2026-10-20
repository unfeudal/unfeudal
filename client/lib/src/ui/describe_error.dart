// SPDX-License-Identifier: Apache-2.0
import 'package:unfeudal_shared/unfeudal_shared.dart';

import '../../l10n/app_localizations.dart';
import '../api/api_client.dart';
import '../app_state.dart';
import '../keys/key_tools.dart';
import '../orgs/host_binding.dart';
import '../ssh/jump_connector.dart';
import '../ssh/port_forwarder.dart';
import '../ssh/ssh_connector.dart';
import '../storage/local_mirror.dart';

/// What happened and what to do, in the UI language. Never an exception's `toString()`: it may hold a secret.
String describeError(AppLocalizations l, Object e) => switch (e) {
  ApiException() => _api(l, e),
  WrongPassword() => l.errorWrongPassword,
  DecryptionFailed() => l.errorDecryptionFailed,
  UnsupportedEnvelope() => l.errorUnsupportedEnvelope,
  UnsupportedKdf() => l.errorUnsupportedKdf,
  WeakKdf() => l.errorWeakKdf,
  WeakPassword() => l.errorWeakPassword(AccountCrypto.minPasswordLength),
  InvalidRecoveryKey() => l.errorInvalidRecoveryKey,
  KeyLabelMismatch() => l.errorKeyLabelMismatch,
  ReadOnlyException() => l.errorReadOnly,
  NetworkException() => l.errorNetwork,
  FormatException() => l.errorProtocol,
  HostKeyRejected(decision: HostKeyDecision.changed) => l.errorHostKeyChanged,
  HostKeyRejected() => l.errorHostKeyUnknown,
  SshAuthFailed() => l.errorSshAuth,
  SshConnectionFailed() => l.errorSshConnection,
  MissingUser() => l.errorMissingUser,
  MissingBinding() => l.errorMissingBinding,
  JumpLoop() => l.errorJumpLoop,
  PortInUse(:final port) => l.errorPortInUse(port),
  ForwardBindFailed(:final port) => l.errorForwardBind(port),
  JumpTooDeep() => l.errorJumpTooDeep,
  JumpHostMissing() => l.errorJumpMissing,
  JumpChainFailed(:final hostName, :final cause) => l.errorJumpHop(
    hostName,
    describeError(l, cause),
  ),
  InvalidKey() => l.errorInvalidKey,
  MirrorTooNew() => l.errorMirrorTooNew,
  InsecureServer() => l.errorInsecureServer,
  PlainHttpRefused() => l.errorPlainHttpRefused,
  _ => l.errorUnexpected('${e.runtimeType}'),
};

// Exhaustive over ApiErrorCode and its reasons, no wildcard: a new code fails to compile until it has a sentence.
String _api(AppLocalizations l, ApiException e) => switch (e.known) {
  null => l.errorUnexpected(e.code),
  ApiErrorCode.invalidRequest => l.errorInvalidRequest,
  ApiErrorCode.unauthorized => switch (e.unauthorizedReason) {
    null when e.reason == null => l.errorUnauthorized,
    UnauthorizedReason.deviceRevoked => l.errorDeviceRevoked,
    UnauthorizedReason.invalidToken ||
    UnauthorizedReason.sessionExpired ||
    null => l.errorSessionExpired,
  },
  ApiErrorCode.forbidden => l.errorForbidden,
  ApiErrorCode.notFound => l.errorNotFound,
  ApiErrorCode.conflict => switch (e.conflictReason) {
    ConflictReason.cursorAhead => l.errorCursorAhead,
    ConflictReason.clientTooOld => l.errorClientTooOld,
    ConflictReason.lastOwner => l.errorLastOwner(
      (e.orgs ?? const []).join(', '),
    ),
    ConflictReason.accountExists => l.errorAccountExists,
    null => l.errorConflict,
  },
  ApiErrorCode.payloadTooLarge => l.errorPayloadTooLarge,
  ApiErrorCode.rateLimited => l.errorRateLimited(e.retryAfter?.inSeconds ?? 1),
  ApiErrorCode.setupDone => l.errorSetupDone,
  ApiErrorCode.featureDisabled => l.errorFeatureDisabled,
  ApiErrorCode.internal => l.errorInternal,
};
