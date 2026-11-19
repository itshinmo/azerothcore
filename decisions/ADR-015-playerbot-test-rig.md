# ADR-015 — Playerbot test rig

- Status: accepted for a test-only rig (approved by the repository owner on 2026-11-17); rig built
  2026-11-17; sweep plan amended by [ADR-016](ADR-016-bot-driven-verification.md); rig paused by
  [ADR-017](ADR-017-bot-rig-paused.md)
- Date: 2026-11-17
- Amends: [ADR-011](ADR-011-world-data-and-content-verification.md) (revisits the playerbot
  rejection under its own revisit clause)
- Related: [ADR-013](ADR-013-server-and-client-before-website.md),
  [ADR-016](ADR-016-bot-driven-verification.md), [ADR-017](ADR-017-bot-rig-paused.md)

## Context

Phase 1 needs behavioural verification at scale: dungeons, battlegrounds, and server soak. A single
human cannot clear every dungeon and raid. ADR-011 rejected playerbots as production infrastructure
because the maintained module requires its own AzerothCore fork
(`mod-playerbots/azerothcore-wotlk`), but it left a revisit clause: behavioural coverage at scale
becoming a hard requirement, "and then in a throwaway branch that never merges into production".
Both halves are met now — Phase 1's measured gate needs behavioural coverage at scale, and this ADR
realizes the revisit as a separate checkout outside the repository, which is throwaway in the same
sense: it never merges into this repository's production surface. The bot ecosystem has since
matured: `mod-dungeon-clear` drives tank-bot
parties through dungeons autonomously and records success rates per run (`.dc test` harness), raid
strategies cover most endgame content, and bots generate real load for soak testing.

## Decision

1. **Test-only rig, outside the repository.** A separate checkout of the playerbot fork plus
   `mod-playerbots` and `mod-dungeon-clear`, with its own binaries, configuration, ports (world
   8086, auth 3725), and databases. Nothing of it enters `modules/`, `src/`, or production
   configuration in this repository.
2. **Findings port back as shared fixes.** A bot failure is evidence: a crash, a stuck encounter,
   or a failed clear maps to a creature, a script, or a data row. Fixes land in *this* repository's
   data (`data/sql/updates/pending_db_*` or `custom/`) or go upstream as PRs. The rig itself is
   never committed here.
3. **Scope.** Dungeons and raids via `mod-dungeon-clear`'s GM harness; battlegrounds and soak via
   bot parties; performance stays bounded to a small bot count. Quest chains stay human-checked —
   bots prove "does not crash", not "plays right".
4. **A production server never runs playerbots.** The rig exists on test infrastructure only; if
   player-facing bots ever become a product feature, that is a new ADR.

## Consequences

- Phase 1's measured exit gate ([ADR-013](ADR-013-server-and-client-before-website.md)) gains a
  data source: per-dungeon success rates from the rig.
- The rig's findings need triage like any report; failures route through the
  [base-game checklist](../runbook/operation/base-game-verification.md) result files.
- The rig inherits this fork's divergence risk: its core is a different fork, so a failure must be
  reproduced on this repository's build before it becomes a fix here. The rig points at a copy of
  this repository's world data for findings that concern this realm's data.
