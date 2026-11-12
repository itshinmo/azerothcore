# ADR-008 — Database access with DBeaver

- Status: accepted
- Date: 2026-11-12
- Supersedes: [ADR-004](ADR-004-database-gui.md)

## Context

The project needs a human-friendly way to browse and edit the game databases. A custom Node GUI was
built in `tools/dbadmin`, but it added a second server, an Origin/session layer, and ongoing
maintenance. It was also harder to use than a native database client. The team works on macOS and
already runs MySQL 8.4 locally.

## Decision

1. Use **DBeaver Community** as the primary database client. Sequel Ace is an acceptable native
   alternative.
2. Do not run an in-repo database GUI server in this phase.
3. Local and test profiles connect directly to MySQL. Production is a **read-only** connection through
   an SSH tunnel, with a read-only database user.
4. Never use `root`; use the least-privilege user for the environment.
5. Back up before any write batch: `make backup`. DBeaver has no audit log or pre-write backup.
6. Keep DBeaver workspace files, query history, and connection profiles out of the repository.
7. Schema/content changes still go through the repo SQL workflow (`data/sql/custom` or
   `data/sql/updates/pending_db_*`) and `make verify-sql` where applicable. DBeaver is for browsing,
   investigation, and small fixes.

## Alternatives considered

- **Custom Node GUI.** Full control and audit, but an extra server, more failure modes, and more code
  to maintain. Removed.
- **Adminer/phpMyAdmin.** Lightweight, but needs PHP and a web server; weaker desktop workflow.
- **CLI only.** Reliable, but poor for browsing large schemas and ad-hoc edits.
- **Sequel Ace.** Good native alternative; DBeaver is chosen for schema/ERD, query management, and
  cross-platform support.

## Consequences

- Simpler local stack and fewer moving parts.
- No built-in audit or write guard; discipline, backups, and read-only production access replace it.
- Future team-wide audited DB access can be a separate project if needed.
