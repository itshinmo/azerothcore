# Security

## Purpose

Define the security boundaries for the server, databases, database GUI, and GM tools.

## Scope

Accounts, RBAC, database users, local tool auth, GM API, secrets, audit, and production access.

## Boundary

Owns access control and secret handling. Does not own game balance or individual command behavior.

## Contract

### Threat model

- A local process or malicious website reaching a localhost GUI.
- A GM account with more permissions than the task needs.
- A database tool using `root` or a shared credential.
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
| local/test GUI user | read/write on local/test | database GUI write mode |
| production GUI user | read-only | database GUI through SSH tunnel |

- No `root` for tools, scripts, or agents.
- Credentials in ignored `.env` or `env/dist/etc/`, never committed.

### Local GUI security

- Bind `127.0.0.1`.
- Random startup token, HttpOnly SameSite=Strict cookie, CSRF token, Host/Origin checks.
- CSP `default-src 'self'`, `frame-ancestors 'none'`, `nosniff`.
- Read-only default; production read-only at route and database user.
- Pre-write backup and audit.

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

- Every privileged action records actor, target, action, arguments, result, timestamp.
- Audit write failure aborts the action.
- Audit records are append-only.
- Audit may contain player identifiers; treat it as sensitive.

## Errors and edge cases

- Wrong token/HMAC: 401, no detail.
- Replayed nonce: 409.
- Missing CSRF or bad Origin: 403.
- Read-only write attempt: 403.
- Audit failure: abort.
- Backup failure: abort the write.

## Observability

- Structured security log with request id, route, status, actor, duration; no secrets.
- Audit table/file.
- Failed-auth rate and source for local tools.

## References

- [specs/database-gui.md](database-gui.md)
- [specs/gm-tools.md](gm-tools.md)
- [.ai/memories/security.md](../.ai/memories/security.md)
- [runbook/gm/rbac-roles.md](../runbook/gm/rbac-roles.md)
