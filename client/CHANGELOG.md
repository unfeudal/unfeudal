# Changelog

## [Unreleased]

### Added
- A new look: a verdigris palette, flat controls with bordered fields, and one sidebar holding the vault picker (Ctrl+1…9), the host tree and search (Ctrl+K, snippets included), the vault's Snippets, Keychain, Members and access, Activity and Trash, and Loquet with Settings and Lock; sections open in place of the sessions, the host inspector docks on the right, and a status bar shows the target, forwards and sync.
- Jump hosts and port forwards: connect through a chain of up to 8 bastions (per host or as a folder default) with each host key checked on its own, and local port forwards on the loopback address that start with the session or from the tab strip.
- Snippets: synced commands to search, edit and insert into the terminal without running them; multi-line text asks first when the terminal does not protect pasted text.
- Terminal: copy and paste with Ctrl+Shift (⌘ on macOS), scrollback search, a right-click menu, reconnect after a hang-up, and a choice of font and text size.
- Loquet, the mascot: reacts to sign-in, connections, host keys and the network, keeps a daily rhythm, a few easter eggs and milestones (counted on this computer only), and can be set to on, sober or off in Settings; a server or an organisation can turn him off.
- Organizations: create or join one, invite members with a safety code, edit folder access and see why someone has a right, manage teams, rotate keys, and administer the instance as its owner.
- Activity and history: the activity log of the account, an organization or the instance, each item's versions with restore, and the trash.
- Security settings: unlock with Windows Hello or Touch ID, change the master password or reset security, export the vault (encrypted by default), delete the account, and open a recovery kit from its file.
- Import `~/.ssh/config`: preview the hosts, keys and jump hosts, pick what to bring in, and see what was left out and why.
- A licences screen with the server's source link and the licence of every bundled font and package; the app is now named Unfeudal on Windows and macOS.
- Org snippets and shared org identities (a key or password the whole folder uses), created in a folder you can edit.
- Leave an organization while still waiting for confirmation; an owner can hand over the owner role and step down.
- The trash shows what a deleted org folder holds and moves items out of it; the Instance Owner opens a deleted organization's activity.

### Fixed
- Editing an item no longer drops fields written by a newer version of the app.
- Restoring an old version never erases the item's password or key, and is offered only with the right to edit.
- An exported activity log is verified; a broken chain is still saved, with a warning.
- An edit of only an item's password or key, made right after a lost server answer, is no longer lost at the next sync.
- Retrying a failed connection keeps its tab in place.
- Terminal search highlights the right text after wide (CJK) characters.
- The password strength meter rates common passwords, keyboard rows and sequences as weak.
