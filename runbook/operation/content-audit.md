# Content audit

## When to use

Before a release, after an upstream sync that carries world data, or after applying project SQL.
It answers one question: which content references are broken in `acore_world` right now.

Read-only. It never writes to the database and never starts a server.

## Prerequisites

- MySQL running, with the world database reachable.
- `env/dist/etc/worldserver.conf` with `WorldDatabaseInfo` pointing at a database whose name ends
  in `_world`.
- `mysql` client in `PATH`, `python3` 3.10 or newer.
- `DataDir` in the same config, so trainer spells resolve against `Spell.dbc`.

The tool reads credentials from the config. Override with `CONTENT_AUDIT_DB_HOST`,
`CONTENT_AUDIT_DB_PORT`, `CONTENT_AUDIT_DB_USER`, `CONTENT_AUDIT_DB_PASSWORD`, and
`CONTENT_AUDIT_DB_NAME` when needed. A database name that does not end in `_world` is refused.

## Steps

1. Run the audit:

   ```bash
   make content-audit
   ```

   Markdown goes to stdout. Exit codes:

   | Code | Meaning |
   |------|---------|
   | 0 | no unwaived blocker findings |
   | 1 | at least one unwaived blocker |
   | 2 | tool, configuration, or database error |

2. For the full machine-readable report:

   ```bash
   make content-audit ARGS="--json /tmp/content-audit.json"
   ```

   Other options: `--config <path>`, `--waivers <path>`, `--data-dir <path>` (client data holding
   `dbc/Spell.dbc`), `--limit <n>` for the Markdown table size.

3. Read the report. Severity:

   - **blocker** — content cannot be reached or runs with a missing script or item.
   - **major** — content is playable but visibly wrong, or a data mismatch that needs a content
     decision.
   - **minor** — data hygiene or cosmetic: flags without matching data, static checks that may not
     reflect runtime behaviour.

   Coverage is a static lower bound: a quest counts as covered only when it has a starter row and
   every objective resolves from database data. Summoned and scripted targets lower the number
   without being broken.

4. Triage. Fix real blockers first; waivers are the last resort, not the first.

5. Waive knowingly. Create `tools/dev/content-audit-waivers.json`:

   ```json
   {
     "waivers": [
       {
         "check": "C-08",
         "entity_kind": "creature_spawn",
         "entity_id": 15066,
         "reason": "scripted through an upstream fix in review",
         "accepted_by": "human"
       }
     ]
   }
   ```

   A waiver matches on check, entity kind, and entity id. A waiver without a reason or an accepting
   person is rejected, duplicate waivers for the same finding are rejected, and a waiver that no
   longer matches any finding is reported as stale and must be removed.

## Verification

```bash
make test-tools
make content-audit ARGS="--limit 3"
make verify-docs
```

Expected: the unit tests pass, the audit runs in a few seconds and prints a report, docs check is
green.

## Troubleshooting

- `mysql client not found in PATH`: install the MySQL client, or run from a shell where `mysql`
  resolves.
- `refusing database '...': name must end with '_world'`: point the config or
  `CONTENT_AUDIT_DB_NAME` at a world database.
- `database query failed`: check that MySQL is running and that the config credentials still work.
  `make doctor` checks both.
- Coverage looks low: check the C-02 and C-04 minors first. A summoned objective target is not a
  defect.

## Escalation

A blocker that appears in upstream data is worth an upstream SQL update under
`data/sql/updates/pending_db_world/`, following `.agents/docs/sql-guidelines.md`. Ask a human before
changing content data.

## References

- [specs/content-pipeline.md](../../specs/content-pipeline.md#verification)
- [decisions/ADR-011-world-data-and-content-verification.md](../../decisions/ADR-011-world-data-and-content-verification.md)
- [runbook/operation/test-realm.md](test-realm.md)
- Findings history: [runbook/audits/README.md](../audits/README.md)
