// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unfeudal_client/l10n/app_localizations.dart';
import 'package:unfeudal_client/src/api/api_client.dart';
import 'package:unfeudal_client/src/app_state.dart';
import 'package:unfeudal_client/src/keys/key_tools.dart';
import 'package:unfeudal_client/src/ssh/jump_connector.dart';
import 'package:unfeudal_client/src/ssh/port_forwarder.dart';
import 'package:unfeudal_client/src/ssh/ssh_connector.dart';
import 'package:unfeudal_client/src/storage/local_mirror.dart';
import 'package:unfeudal_client/src/ui/describe_error.dart';
import 'package:unfeudal_shared/unfeudal_shared.dart';

void main() {
  late AppLocalizations l;
  setUpAll(
    () async => l = await AppLocalizations.delegate.load(const Locale('en')),
  );
  String d(Object e) => describeError(l, e);

  test('every API code has its own sentence', () {
    final texts = {
      for (final c in ApiErrorCode.values) d(ApiException(c.wire, c.status)),
    };
    expect(texts, hasLength(ApiErrorCode.values.length));
    expect(
      texts.every((t) => t.isNotEmpty && !t.contains('Exception')),
      isTrue,
    );
  });

  test('reasons, seconds and unknown codes', () {
    expect(
      d(ApiException('unauthorized', 401, reason: 'device_revoked')),
      l.errorDeviceRevoked,
    );
    expect(
      d(ApiException('unauthorized', 401, reason: 'whatever')),
      l.errorSessionExpired,
    );
    expect(d(ApiException('unauthorized', 401)), l.errorUnauthorized);
    expect(
      d(ApiException('conflict', 409, reason: 'cursor_ahead')),
      l.errorCursorAhead,
    );
    expect(
      d(ApiException('conflict', 409, reason: 'client_too_old')),
      l.errorClientTooOld,
    );
    expect(
      d(
        ApiException(
          'conflict',
          409,
          reason: 'last_owner',
          orgs: ['Acme', 'Beta'],
        ),
      ),
      l.errorLastOwner('Acme, Beta'),
    );
    expect(
      d(ApiException('conflict', 409, reason: 'account_exists')),
      l.errorAccountExists,
    );
    expect(
      d(
        ApiException(
          'rate_limited',
          429,
          retryAfter: const Duration(seconds: 12),
        ),
      ),
      l.errorRateLimited(12),
    );
    expect(d(ApiException('teapot', 418)), 'Unexpected error (teapot).');
  });

  test('crypto, local and SSH errors', () {
    expect({
      d(const WrongPassword()),
      d(const DecryptionFailed()),
      d(const UnsupportedEnvelope('x')),
      d(const UnsupportedKdf('x')),
      d(const WeakKdf()),
      d(const WeakPassword()),
      d(const InvalidRecoveryKey()),
      d(const KeyLabelMismatch('x')),
    }, hasLength(7)); // the two "update the app" errors share a sentence
    expect(d(const ReadOnlyException()), l.errorReadOnly);
    expect(d(NetworkException(Exception('x'))), l.errorNetwork);
    expect(d(const FormatException('bad')), l.errorProtocol);
    expect(
      d(const HostKeyRejected(HostKeyDecision.changed)),
      l.errorHostKeyChanged,
    );
    expect(
      d(const HostKeyRejected(HostKeyDecision.unknown)),
      l.errorHostKeyUnknown,
    );
    expect(d(const SshAuthFailed()), l.errorSshAuth);
    expect(d(const SshConnectionFailed()), l.errorSshConnection);
    expect(d(const MissingUser()), l.errorMissingUser);
    expect(d(const InvalidKey()), l.errorInvalidKey);
    expect(d(const MirrorTooNew(2)), l.errorMirrorTooNew);
    expect(d(const InsecureServer()), l.errorInsecureServer);
    expect(d(const PlainHttpRefused()), l.errorPlainHttpRefused);
    expect(
      d(StateError('secret detail')),
      'Unexpected error (StateError).',
    ); // never toString()
  });

  test('jump errors', () {
    final l = lookupAppLocalizations(const Locale('en'));
    expect(describeError(l, JumpLoop(['a', 'b', 'a'])), l.errorJumpLoop);
    expect(describeError(l, JumpTooDeep(['t'])), l.errorJumpTooDeep);
    expect(describeError(l, JumpHostMissing('x')), l.errorJumpMissing);
    expect(
      describeError(l, JumpChainFailed('b', 'bastion', 0, const MissingUser())),
      l.errorJumpHop('bastion', describeError(l, const MissingUser())),
    );
  });

  test('forward errors', () {
    final l = lookupAppLocalizations(const Locale('en'));
    expect(describeError(l, const PortInUse(8080)), l.errorPortInUse(8080));
    expect(
      describeError(l, const ForwardBindFailed(8080, null)),
      l.errorForwardBind(8080),
    );
  });
}
