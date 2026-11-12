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

### Accounts and RBAC

- GM accounts are named; no shared accounts.
- Roles are least-privilege permission sets, not broad `gmlevel` grants.
- High/critical actions require human approval and an audit entry.
- Production GM accounts are separate from test accounts.

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
- [runbook/database/dbeaver.md](../runbook/database/dbeaver.md)
- [runbook/gm/rbac-roles.md](../runbook/gm/rbac-roles.md)
