# Runbook

Procedures for humans: setup, operation, database, GM, and troubleshooting. A runbook answers "how do
I do it"; behavior lives in `specs/`.

## Conventions

- Start from [the runbook template](../.ai/templates/runbook.md): when to use, prerequisites, steps,
  verification, troubleshooting, escalation, references.
- Commands are real and tested. Unknowns are `<!-- TODO -->`, not invented.
- No credentials, tokens, production hostnames, or player data. Name the secret, never its value.
- If a procedure changes, update the runbook in the same change.

## Index

### Development

- [setup-macos.md](development/setup-macos.md) — Homebrew dependencies, MySQL, build, install.
- [build-and-install.md](development/build-and-install.md) — CMake options, build, install, tools.
- [database-bootstrap.md](development/database-bootstrap.md) — create and populate the three databases.
- [config-changes.md](development/config-changes.md) — server and tool configuration.
- [worktrees-and-branches.md](development/worktrees-and-branches.md) — one task, one worktree.
- [commands.md](development/commands.md) — every build, test, server, database, and verification command.

### Operation

- [start-stop.md](operation/start-stop.md) — start, stop, restart, signals.
- [health-check.md](operation/health-check.md) — ports, DB, data, logs, login.
- [logs-and-monitoring.md](operation/logs-and-monitoring.md) — log files, levels, metrics.
- [backup-restore.md](operation/backup-restore.md) — dump, verify, restore.
- [apply-sql-update.md](operation/apply-sql-update.md) — pending and custom SQL.
- [rollback.md](operation/rollback.md) — database, binary, and config rollback.
- [test-realm.md](operation/test-realm.md) — isolated realm for e2e and risky changes.
- [production-deploy.md](operation/production-deploy.md) — Linux production target and deploy.

### Database

- [dbeaver.md](database/dbeaver.md) — connect, browse, query, and safely edit with DBeaver.
- [schema-guide.md](database/schema-guide.md) — key tables and relationships.
- [common-queries.md](database/common-queries.md) — support and content queries.
- [erd.md](database/erd.md) — curated relationship map.
- [id-registry.md](database/id-registry.md) — reserved custom IDs.

### GM

- [command-handbook.md](gm/command-handbook.md) — command reference and danger levels.
- [rbac-roles.md](gm/rbac-roles.md) — least-privilege roles.
- [item-grant-refund.md](gm/item-grant-refund.md) — grants, mail, refunds.
- [ban-appeal.md](gm/ban-appeal.md) — ban and appeal procedure.
- [incident-response.md](gm/incident-response.md) — contain, diagnose, restore, record.

### Troubleshooting

- [server-wont-start.md](troubleshooting/server-wont-start.md)
- [database-errors.md](troubleshooting/database-errors.md)
- [auth-login-failures.md](troubleshooting/auth-login-failures.md)
- [map-data-missing.md](troubleshooting/map-data-missing.md)
- [performance.md](troubleshooting/performance.md)

### Audits

- [README.md](audits/README.md) — audit report format and index.
