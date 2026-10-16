# Unfeudal

Self-hosted, end-to-end encrypted SSH client and vault.

Your hosts, keys and passwords are encrypted on your devices before they reach your own server. The server stores and syncs ciphertext; it never sees your vault.

> **Status: in development.** There is no release yet. Watch the repository or the milestones to follow progress.

## What it will do

- **Desktop client** (Windows, macOS): terminal, SSH hosts, keys, port forwarding, jump hosts, snippets.
- **Self-hosted server** (Docker, SQLite or PostgreSQL): sync across your devices, end-to-end encrypted.
- **Organizations**: share folders of hosts with a team, with per-folder permissions and an audit log.
- **No telemetry.** The app only talks to the server you choose.

## Licences

| Part | Licence |
|---|---|
| `server/` | AGPL-3.0-or-later |
| `client/`, `shared/` | Apache-2.0 |

Each folder carries its own `LICENSE` file and every source file starts with its SPDX header.

## Contributing

Issues and pull requests are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md). Security reports go through [SECURITY.md](SECURITY.md), never a public issue.

Mirror: [git.killiandalcin.fr/unfeudal/unfeudal](https://git.killiandalcin.fr/unfeudal/unfeudal) (read-only; issues and pull requests here on GitHub).
