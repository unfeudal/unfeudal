# Changelog

## [Unreleased]

### Added
- Organizations: shared vaults with owners, admins and members, teams, per-folder access rules, invitations by link or email, folder key handoff and rotation, and Instance Owner administration of accounts, organizations and invitations.
- Audit trail: tamper-evident activity chains for each account, organization and the instance, with SSH sessions, port forwards and secret reveals reported by clients, item version history, and a daily job that purges expired audit events, raw IP addresses, old versions and trash.
- Mail over SMTP (STARTTLS, implicit TLS or plain): security notices for new sign-ins, password changes, recovery key use and sign-in lockouts, in English or French; account deletion; the `transfer-owner` command; a clean shutdown that lets open requests and queued mails finish.
- The container image names its source and licence, and the documentation covers configuration, HTTPS, mail, backup, restore, upgrades and every command.

### Changed
- The container image runs on Debian 13 (trixie), the release its build stage uses.
- A folder's activity view reads through an index of each event's targets (migration 5 builds it from the existing events) instead of scanning the whole organization chain.
- Sync and the admin list of organizations read an organization's data in a few queries instead of one per folder or per organization.

### Fixed
- A configuration file with broken YAML stops the server with exit code 2 and never prints its content.
- A sign-in refused because the server is busy no longer counts as a failed attempt.
- A sign-in waiting for the password check goes before other password hashing, and an admitted check is never turned away once its attempt is counted.
- Deleting an account removes every raw IP address of its actions, in every activity chain.
