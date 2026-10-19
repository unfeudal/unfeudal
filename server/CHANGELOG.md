# Changelog

## [Unreleased]

### Added
- Organizations: shared vaults with owners, admins and members, teams, per-folder access rules, invitations by link or email, folder key handoff and rotation, and Instance Owner administration of accounts, organizations and invitations.
- Audit trail: tamper-evident activity chains for each account, organization and the instance, with SSH sessions, port forwards and secret reveals reported by clients, item version history, and a daily job that purges expired audit events, raw IP addresses, old versions and trash.
- Mail over SMTP (STARTTLS, implicit TLS or plain): security notices for new sign-ins, password changes, recovery key use and sign-in lockouts, in English or French; account deletion; the `transfer-owner` command; a clean shutdown that lets open requests and queued mails finish.
- The container image names its source and licence, and the documentation covers configuration, HTTPS, mail, backup, restore, upgrades and every command.
