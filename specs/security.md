# Security

## Purpose

Define the security boundaries for the server, databases, direct database clients, and GM tools.

## Scope

Accounts, RBAC, database users, client access, GM API, secrets, audit, and production access.

## Boundary

Owns access control and secret handling. Does not own game balance or individual command behavior.

## Contract

### Threat model

- A local process or malicious website reaching a local database client.
- A GM account with more permissions than the task needs.
- A database tool using `root` or a shared credential.
- A database client connected to production with write access.
- A GM API exposed beyond localhost/VPN or missing replay protection.
- A secret in a commit, log, chat, or error message.
- A player or compromised account reaching a GM path.
- A bad write corrupting player data.
- A modified client that changes local collision, animation, or data files.

### Accounts and RBAC

- GM accounts are named; no shared accounts.
- Roles are least-privilege permission sets, not broad `gmlevel` grants.
- High/critical actions require human approval and an audit entry.
- Production GM accounts are separate from test accounts.

### Client trust and anti-cheat

- The authserver authenticates the account and accepts only a configured client build (12340). By
  default it does not verify the executable checksum. `StrictVersionCheck=1` adds a SHA1 executable
  proof using the hashes in `build_info`. MPQ files are not hashed at login.
- Warden is a runtime anti-cheat: memory, Lua, driver/module, and the configured MPQ entries from
  `warden_checks`. It is not a full client file-integrity scan. It only covers `Win` clients:
  `WorldSession::InitWarden` creates `WardenWin` for `Win` and leaves the `OSX` branch disabled
  because it crashed the client, so a macOS client gets no checks even with `Warden.Enabled=1`.
  Warden is enabled on local and production configurations and disabled on the e2e test realm. When
  enabled, the worldserver also rejects an account whose stored OS is not `Win` or `OSX` before the
  session starts (`network`: invalid client OS).
- The client is authoritative for rendering, local collision, and animation. The server validates
  movement packets and some limits, and applies world state such as underwater and breath from the
  map and VMap liquid. A modified client can skip the swim animation or walk underwater; the server
  does not force the animation.
- Server-side water movement validation (swim flag vs `GetLiquidData()` status, swim-speed
  enforcement) is not implemented and is out of scope.
- The test realm is not an anti-cheat environment. Do not judge cheat detection there.

### Database users

| User | Access | Use |
|------|--------|-----|
| server user | read/write on the three databases | `authserver`, `worldserver` |
| local/test client user | read/write on local/test | DBeaver local/test connections |
| production client user | read-only | DBeaver through an SSH tunnel |

- No `root` for tools, scripts, or agents.
- Credentials live in the client's own credential store or ignored `.env`/`env/dist/etc/`, never in
  a commit.

### Direct database clients

- Use DBeaver (recommended) or another native MySQL client. See
  [runbook/database/dbeaver.md](../runbook/database/dbeaver.md).
- Production is a **read-only** connection through an SSH tunnel. Never enable writes on it.
- Keep autocommit off for edits; use a transaction where MySQL supports it.
- Back up before a write batch: `make backup`.
- The client has no built-in audit or pre-write backup. The backup and the repo SQL review are the
  safety net.
- Do not store DBeaver workspace files, query history, or connection profiles in the repository.

### GM API security

- Server module API, not direct database writes.
- HMAC-signed requests with nonce and timestamp; replay window; rate limit.
- Localhost or private VPN bind.
- Read-only endpoints first; writes require a role and audit.
- No secrets in the frontend.

### Future website security

Website work starts in Phase 3, after the base game and custom content ([ADR-013](../decisions/ADR-013-server-and-client-before-website.md)).

- The browser talks to a website BFF, not directly to the GM API.
- The admin BFF holds the GM API HMAC secret. The public BFF and browser never receive it.
- Web identity is separate from game SRP6. Link a web identity to a game account; do not reuse game
  session keys.
- Web login uses passkeys, OAuth, or an Argon2id password hash. Destructive actions require MFA or
  re-authentication.
- Public pages, account/identity pages, and the GM dashboard are separate security zones. The GM
  dashboard is behind VPN/SSO or a separate admin origin.
- The read API uses one shared HMAC secret. Write endpoints add a signed `X-GM-Actor` game account
  id, an RBAC permission check, and an audit row; website login alone grants no GM rights.
- The website and BFF never write directly to the database.

### Secrets

- Never log passwords, tokens, session keys, or full connection strings.
- Redact player data in SQL parameters where possible.
- Rotate a credential that appears in a log or commit.
- Report an exposed secret to the human immediately; do not quote it.

### Audit

- Every privileged GM action records actor, target, action, arguments, result, timestamp.
- Audit write failure aborts the action.
- Audit records are append-only.
- Audit may contain player identifiers; treat it as sensitive.
- Direct SQL edits are not audited by the game; the DB backup and change review are the record.

## Errors and edge cases

- Wrong DB credential: fix the client connection, do not weaken the user.
- Read-only write attempt: expected on production; use a local/test connection.
- Backup failure: abort the write.
- Lost DB connection: no blind retry of a write; verify state first.
- A secret in a client profile: rotate it and remove the profile.

## Observability

- MySQL error log and slow query log.
- Server `Errors.log` for data errors.
- Client query history is local; do not commit it.
- No central audit for direct DB edits in v1.

## References

- [specs/database.md](database.md)
- [specs/gm-tools.md](gm-tools.md)
- [.ai/memories/security.md](../.ai/memories/security.md)
- [runbook/troubleshooting/stormwind-water.md](../runbook/troubleshooting/stormwind-water.md)
- [runbook/troubleshooting/test-realm-stops.md](../runbook/troubleshooting/test-realm-stops.md)
- [runbook/database/dbeaver.md](../runbook/database/dbeaver.md)
- [runbook/gm/rbac-roles.md](../runbook/gm/rbac-roles.md)
