# ADR-002 — Custom content isolation and ID ranges

- Status: accepted
- Date: 2026-11-12

## Context

The upstream convention keeps `modules/*`, `data/sql/custom/*`, and `src/server/scripts/Custom/*`
gitignored. For a private server that is a data-loss risk: custom work is not versioned, not reviewed,
and not reproducible. At the same time, editing upstream core files makes future upstream merges
painful.

## Decision

1. **Track project code.** Project C++ lives in `modules/mod-*` and is tracked. Do not add project
   content to `src/server/scripts/Custom/`.
2. **Track project SQL.** `data/sql/custom/db_auth`, `db_characters`, and `db_world` are tracked.
   Project SQL must be re-applicable: `CREATE TABLE IF NOT EXISTS`, `DELETE` + `INSERT`, `REPLACE`,
   guarded `UPDATE`.
3. **Keep upstream trees immutable.** `data/sql/base/`, `archive/`, and `updates/db_*/` are never
   edited. Upstream-shaped changes use `updates/pending_db_*/`.
4. **Reserve IDs.**
   - items `900000–909999`
   - creatures `910000–919999`
   - quests `920000–929999`
   - gameobjects `930000–939999`
   - spells `940000–949999`
   - misc `950000–959999`
   - maps `1000+`
   The registry is `runbook/database/id-registry.md`; every new ID is recorded before use.
5. **Reuse client assets first.** New zones, maps, item visuals, spell visuals, and area triggers need
   a client MPQ/DBC patch plus map extraction. Until that pipeline is approved, use existing assets.
6. **No content now.** The policy is recorded so future work starts correctly. Current work is
   infrastructure and tooling.

## Alternatives considered

- **Edit core directly.** Fastest for one-off changes; upstream merges become conflict-heavy.
- **Separate private content repo.** Keeps this fork clean, but adds a second history and a sync step.
- **Keep the upstream gitignore.** Zero setup, but custom work is unversioned and unreviewable.
- **Use one global ID range.** Simpler rule, but type collisions and harder auditing.

## Consequences

- Custom work is reviewable, reproducible, and backed up with the repo.
- Upstream files stay mergeable.
- Every custom ID needs a registry entry.
- A client patch is a separate, explicit project with its own release process.
