---
description: RBAC, database users, DBeaver access, GM API, secrets, and audit. Read before adding a tool or permission.
last-verified: 2026-11-12
---

# Security

The contract is [specs/security.md](../../specs/security.md).

## Principles

- Least privilege everywhere: database users, GM roles, client connections, API scopes.
- No secrets in the repository, docs, logs, tests, or chat.
- Production writes are human-only.
- Every privileged GM or API action is auditable. Direct SQL edits are not audited by the game.
- Local-only by default; remote access goes through a VPN or SSH tunnel.

## Database users

- `acore` is the server user; it needs read/write on the three game databases.
- DBeaver uses separate users: local/test write user, production read-only user.
- Never use `root` for DBeaver, scripts, or agents.
- Credentials live in DBeaver's own store, `.env` (ignored), or `env/dist/etc/` (ignored), never in a
  commit.

## Database access

- Use DBeaver for browsing and querying: [runbook/database/dbeaver.md](../../runbook/database/dbeaver.md).
- Production is a read-only connection through an SSH tunnel.
- Back up before a write batch; DBeaver has no audit or pre-write backup.
- Keep autocommit off for edits and do not commit DBeaver workspace files.

## GM tools

- RBAC-gated commands; use the smallest role.
- The future server website BFF calls the GM API, not the database directly.
- HMAC-signed requests, replay protection, rate limit, localhost/VPN bind.
- Audit every action: actor, target, command, arguments, result, timestamp.
- The in-game addon wraps existing commands and does not bypass server checks.

## Secrets

- Never log passwords, tokens, session keys, or full connection strings.
- Redact SQL parameters that may contain player data.
- Rotate any credential that appears in a log or a commit.
- If a secret is exposed, report it to the human immediately; do not quote it in chat or an issue.
