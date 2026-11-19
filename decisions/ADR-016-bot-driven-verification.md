# ADR-016 — Bot-driven verification: dungeon clears assumed green, raids verified

- Status: accepted, amended by [ADR-017](ADR-017-bot-rig-paused.md)
- Date: 2026-11-19
- Amends: the sweep plan in [ADR-015](ADR-015-playerbot-test-rig.md)

## Context

ADR-015 put playerbots in a throwaway test rig outside the repository. The classic 5-man sweep
finished 24/27 green; the two real failures (`lbrs`, `brd-db`) were rig-harness defects, confirmed
fixed by replay. `bfd` keeps two open harness defects. The TBC and WotLK 5-man sweeps were queued
but never run.

The classic sweep cost about three hours of wall time and found no content defect in this
repository. Repeating that cost per expansion tests content no player has reported as broken.

## Decision

1. Dungeon clears are assumed to work. The classic sweep is the record; the TBC and WotLK 5-man
   batches are cancelled.
2. A player report is the trigger to run a dungeon again. Reproduce it in the rig, record the run in
   the ledger, and fix the cause: content in `data/sql` in this repository, harness defects in the
   rig only.
3. Raids are verified proactively: classic `mc, bwl, zg, aq20, aq40, ony` and TBC
   `gruul, kara, kara-chess`, on the owner's go, two parties concurrent, 10-bot default, one rerun
   at the map cap before a finding is filed.
4. The rig keeps its databases, worktree, traces, and ledger as reproduction material for future
   reports. Playerbots stay out of production and out of this repository
   ([ADR-011](ADR-011-world-data-and-content-verification.md), [ADR-015](ADR-015-playerbot-test-rig.md)).

## Consequences

- Dungeon coverage becomes report-driven; an unreported dungeon can stay broken until a player
  finds it.
- Raid coverage stays proactive, because players rarely report raid encounters precisely.
- The rig becomes long-lived debugging infrastructure, not a one-off sweep tool.

## References

- [ADR-011](ADR-011-world-data-and-content-verification.md)
- [ADR-015](ADR-015-playerbot-test-rig.md)
- [runbook/operation/playerbot-rig.md](../runbook/operation/playerbot-rig.md)
- [runbook/audits/2026-11-17-bot-dungeon-runs.md](../runbook/audits/2026-11-17-bot-dungeon-runs.md)
