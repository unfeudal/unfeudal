# Running the server

## Configuration

Start from [`config.example.yaml`](../config.example.yaml) and point `UNFEUDAL_CONFIG_FILE` at your copy, or set each key as an environment variable `UNFEUDAL_<KEY>` (upper case). The environment wins over the file; keep secrets (`setup_token`, `smtp_password`) there.

The server refuses to start on an unknown key, a bad value or a missing `public_url`, and says which key is wrong.

On the first start the server prints a one-time setup token in its logs (unless `setup_token` is set). The client asks for it to create the Instance Owner account.

## HTTPS

Run the server behind a reverse proxy that terminates TLS. [`docker-compose.yml`](../docker-compose.yml) and [`Caddyfile.example`](../Caddyfile.example) do this on one host:

- the container listens on `127.0.0.1:8080` only;
- the compose network uses a fixed subnet (`172.30.0.0/24`), so the proxy reaches the container from the gateway `172.30.0.1`;
- `trusted_proxies` lists that address: only it may set `X-Forwarded-For`, which rate limits and the audit log use.

`plain_http_lan` (off by default) allows an `http://` `public_url` for a LAN address only. Clients ask before signing in over plain HTTP and keep an "unencrypted" banner while connected.

## Mail

Without `smtp_host`, no mail is sent. With it, set `smtp_port`, `smtp_tls` (`starttls`, `implicit` on port 465, or `none`), `smtp_user`, `smtp_password` and `smtp_from`.

The server sends invitations (`smtp_invites`) and, with `security_emails`, notices of new sign-ins, password changes, recovery key use and sign-in lockouts, in the account's language. A mail failure never fails or delays a request.

## Backup

SQLite:

```sh
docker compose exec unfeudal unfeudal-server backup /data/backup-2026-11-02.db
```

Copy the backup **and** `secret.key` together, and keep both readable by the server user only (mode 600). The database without `secret.key` cannot verify existing sessions.

PostgreSQL: use `pg_dump` (the `backup` command refuses PostgreSQL), and keep `secret.key` with the dump.

## Restore

1. Stop the server.
2. Put back the database (or restore the `pg_dump`) and `secret.key`.
3. Run `unfeudal-server new-epoch`: clients then show a banner to accept or refuse the restored state instead of silently going back in time.
4. Start the server.

## Upgrade

1. Back up first.
2. Pull the new image and restart: migrations run at start.

A database migrated by a newer server refuses an older one. To downgrade, restore the backup taken before the upgrade.

## Commands

| Command | What it does |
|---|---|
| `unfeudal-server` | Runs the server. |
| `unfeudal-server healthcheck` | Exits 0 when the server answers (the image's `HEALTHCHECK`). |
| `unfeudal-server backup <path>` | Writes a consistent SQLite copy. |
| `unfeudal-server new-epoch` | Marks a restore, so clients notice it. |
| `unfeudal-server transfer-owner <email>` | Makes that enabled account the Instance Owner; the only way to change it. |

## Stopping

`docker stop` sends SIGTERM and waits 10 seconds. The server stops accepting connections, lets open requests and queued mails finish within 8 seconds, then closes the database.
