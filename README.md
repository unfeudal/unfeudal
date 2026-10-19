# Unfeudal

Self-hosted, end-to-end encrypted SSH client and vault.

Your hosts, keys and passwords are encrypted on your devices before they reach your own server. The server stores and syncs ciphertext; it never sees your vault. The server is AGPL, the desktop client Apache-2.0, and neither sends telemetry: the app only talks to the server you choose and your SSH hosts.

> **Status: in development.** There is no release yet. Watch the repository or the milestones to follow progress.

## What it does

- **Desktop client** (Windows, macOS): terminal, SSH hosts, keys, port forwarding, jump hosts, snippets, `~/.ssh/config` import, biometric unlock.
- **Self-hosted server** (Docker, SQLite or PostgreSQL): sync across your devices, end-to-end encrypted.
- **Organizations**: share folders of hosts with a team, with per-folder permissions and an audit log.

## Install the server

1. Copy [`docker-compose.yml`](docker-compose.yml) and [`Caddyfile.example`](Caddyfile.example) (as `Caddyfile`) to the host, and replace `vault.example.org` with your domain.
2. Set `UNFEUDAL_PUBLIC_URL` to the address clients will use.
3. `docker compose up -d`, then read the setup token printed once in the logs: `docker compose logs unfeudal`.

Configuration, HTTPS, mail, backup, restore and upgrades: [docs/operations.md](docs/operations.md).

## Install the client

- **Windows**: the installer (`…-windows-x64-setup.exe`) or the zip. Builds are unsigned for now, so SmartScreen warns on first launch.
- **macOS**: the `.dmg`. Builds are unsigned: the first time, right-click the app → Open.

Verify a download with `SHA256SUMS`, or its provenance with:

```sh
gh attestation verify <file> --repo unfeudal/unfeudal
```

## Licences

| Part | Licence |
|---|---|
| `server/` | AGPL-3.0-or-later |
| `client/`, `shared/`, `tool/` | Apache-2.0 |

Each folder carries its own `LICENSE` file and every source file starts with its SPDX header. The server's source: https://github.com/unfeudal/unfeudal (announced by every server in `/api/info`).

**FAQ.** Running the unmodified server, even for your company, creates no obligation. If you modify the server and let others use it, point `source_url` to your modified source.

## Contributing

Issues and pull requests are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md). Security reports go through [SECURITY.md](SECURITY.md), never a public issue. Releases: [docs/release.md](docs/release.md).

Mirror: [git.killiandalcin.fr/unfeudal/unfeudal](https://git.killiandalcin.fr/unfeudal/unfeudal) (read-only; issues and pull requests here on GitHub).
