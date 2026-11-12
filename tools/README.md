# Project tooling

This directory holds project-specific tooling. Upstream helper scripts live in `apps/`; do not
confuse the two.

| Path | Purpose | Status |
|------|---------|--------|
| `dev/` | doctor, server lifecycle, backup, verification | available |
| `gm-panel/` | web GM panel frontend | phase 4 |
| `gm-addon/` | in-game GM addon | phase 4 |

Database access is external: DBeaver, documented in `runbook/database/dbeaver.md`. There is no
in-repo database GUI server.

Rules:

- Tool dependencies are pinned in a `package.json`/lockfile next to the tool.
- Local state and secrets live in ignored files (`node_modules/`, `.env`).
- Every tool has a README, a test plan, and a runbook entry.
- No tool writes to production without human approval.

See [runbook/README.md](../runbook/README.md) for the procedures.
