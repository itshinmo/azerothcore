# ADR-004 — Database GUI

- Status: accepted
- Date: 2026-11-12

## Context

Humans need to read and modify the game databases without raw SQL and without `root`. No GUI exists in
the repository. Available tools: custom Node app, Adminer, phpMyAdmin, DBeaver. Node 26 is installed;
PHP and Docker are not. The GUI will handle player data and must not become a security hole.

## Decision

1. **Custom Node 26 web GUI** in `tools/dbadmin/`: built-in `http`, `mysql2` as the only runtime
   dependency, server-rendered HTML, small vanilla JS/CSS. No framework, no build step.
2. **Localhost only.** Bind `127.0.0.1`. No public binding. Remote production access is an SSH tunnel.
3. **Authentication.** Random 32-byte token printed at startup, HttpOnly SameSite=Strict cookie,
   timing-safe comparison. Optional local username/password if the Mac is shared.
4. **Request protection.** Host-header allowlist, CSRF token on every state-changing form, Origin
   check, CSP `default-src 'self'`, `frame-ancestors 'none'`, `nosniff`.
5. **Least privilege.** Separate DB users for local/test write and production read-only. Never `root`.
6. **Read-only production.** The production profile is read-only at the route and by the database
   user. Writes require a local/test profile.
7. **Write guard.** Write mode off by default; typed confirmation; single statement; dangerous SQL
   blocked; row-count preview; transaction where supported; pre-write backup; audit entry.
8. **Audit.** `var/dbadmin/audit.db` via `node:sqlite`: actor, profile, SQL, before/after, row count,
   duration, success, backup path. Append-only, redacted.
9. **Features.** Schema browser, row browser/editor, SQL runner, saved game queries, pending SQL
   import, audit viewer, ERD, backups.

## Alternatives considered

- **Adminer.** Mature, single PHP file, but needs PHP and has weaker safety rails and no game-specific
  workflow.
- **phpMyAdmin.** Familiar, feature-rich, heavier PHP stack and more surface.
- **DBeaver.** Best for individual power users, but no shared web UI, no audit, no backup integration.
- **Direct SQL only.** No GUI; higher operator error risk.

## Consequences

- One `mysql2` dependency and a tool to maintain.
- The tool can enforce project-specific safety and audit.
- It must be tested and reviewed like production code.
- A future shared/team mode needs a separate decision: auth, HTTPS, VPN.
