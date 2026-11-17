# Bot dungeon runs — tracking ledger

One dungeon per session, on the repository owner's explicit go. Every run's start and end lines are
copied here; failures become findings in the [checklist](../operation/base-game-verification.md)
results or `data/sql` fixes.

| # | Date | Run id | Dungeon | Result | Bosses | Duration | Notes |
|---|------|--------|---------|--------|--------|----------|-------|
| 1 | 2026-11-17 | tr-20261117-231354-1 | Deadmines (`deadmines`) | success | 8/8 | 2057s (~34 min) | Smoke test. Mid-run the freeze detector fired at the Gilnid standoff (no progress 300s) and the run self-recovered. Loot step held 60s for Cookie before ending. |
| 2 | 2026-11-18 | tr-20261118-001306-2 | Shadowfang Keep (`sfk`) | success | 8/8 | 1261s (~21 min) | No freeze events. Fastest run so far. |

Next runs start only on the owner's explicit go, one dungeon per go.

## How to read this table

- `result=success` = every boss died and the run ended cleanly (`TESTRUN END ... bosses=N/N`).
- A `FROZEN` line is the run's own watchdog: it fires when the party makes no progress for 300s.
  If the run still ends `success`, the party recovered; if it ends `fail`, the frozen position is
  the finding.
- Findings worth a fix get a row in the findings section below with the creature entry and the
  proposed fix.

## Findings

(none yet)
