---
description: RBAC, database users, GUI auth, GM API, secrets, and audit. Read before adding a tool or permission.
last-verified: 2026-11-12
---

# Security

The contract is [specs/security.md](../../specs/security.md).

## Principles

- Least privilege everywhere: database users, GM roles, GUI tokens, API scopes.
- No secrets in the repository, docs, logs, tests, or chat.
- Production writes are human-only.
- Every privileged action is auditable.
- Local-only by default; remote access goes through a VPN or SSH tunnel.

## Database users

- `acore` is the server user; it needs read/write on the three game databases.
- The GUI uses separate users: local/test write user, production read-only user.
- Never use `root` for the GUI, scripts, or agents.
- Credentials live in `.env` (ignored) or `env/dist/etc/` (ignored), never in a commit.

## Database GUI

- Bind `127.0.0.1`.
- Random startup token, HttpOnly SameSite=Strict cookie, CSRF token, Origin/Host checks.
- CSP `default-src 'self'`, `frame-ancestors 'none'`.
- Read-only default; production profile is read-only at the route and the database user.
- Pre-write backup and audit record for every write batch.
- Remote production access through `ssh -L`.

## GM tools

- RBAC-gated commands; use the smallest role.
- The web GM panel (phase 4) calls a server module API, not the database directly.
- HMAC-signed requests, replay protection, rate limit, localhost/VPN bind.
- Audit every action: actor, target, command, arguments, result, timestamp.
- The in-game addon wraps existing commands and does not bypass server checks.

## Secrets

- Never log passwords, tokens, session keys, or full connection strings.
- Redact SQL parameters that may contain player data.
- Rotate any credential that appears in a log or a commit.
- If a secret is exposed, report it to the human immediately; do not quote it in chat or an issue.
