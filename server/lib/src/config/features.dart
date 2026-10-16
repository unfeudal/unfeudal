// SPDX-License-Identifier: AGPL-3.0-or-later

enum Flag {
  orgs('orgs'),
  teams('teams'),
  userOverrides('user_overrides'),
  invitesFromOrgs('invites_from_orgs'),
  smtpInvites('smtp_invites'),
  securityEmails('security_emails'),
  audit('audit'),
  clientEvents('client_events'),
  itemHistory('item_history'),
  recoveryKit('recovery_kit'),
  plainHttpLan('plain_http_lan'),
  reveal('reveal'),
  biometricUnlock('biometric_unlock'),
  sshConfigImport('ssh_config_import'),
  mascot('mascot');

  const Flag(this.wire);

  final String wire;

  static Flag? fromWire(String wire) {
    for (final flag in values) {
      if (flag.wire == wire) return flag;
    }
    return null;
  }
}

/// All flags on by default except [Flag.plainHttpLan].
class Features {
  Features(this._overrides);

  final Map<Flag, bool> _overrides;

  static const _public = {Flag.recoveryKit, Flag.plainHttpLan, Flag.mascot};

  bool enabled(Flag flag) => _overrides[flag] ?? flag != Flag.plainHttpLan;

  /// Without a token: `sync` plus the enabled flags among recovery_kit, plain_http_lan and mascot.
  List<String> publicCapabilities() => _capabilities(_public);

  /// With a valid access token: `sync` plus every enabled flag.
  List<String> capabilities() => _capabilities(Flag.values);

  List<String> _capabilities(Iterable<Flag> flags) => [
    'sync',
    for (final flag in flags)
      if (enabled(flag)) flag.wire,
  ]..sort();
}
