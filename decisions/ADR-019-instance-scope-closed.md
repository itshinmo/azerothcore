# ADR-019 — Instance verification scope closed; player reports drive remaining coverage

- Status: accepted
- Date: 2026-11-20
- Decided by: the owner
- Amends: [ADR-013](ADR-013-server-and-client-before-website.md) (Phase 1 measured gate),
  [ADR-016](ADR-016-bot-driven-verification.md) (proactive raid coverage ends),
  [ADR-017](ADR-017-bot-rig-paused.md) (standing manual verification ends)

## Context

The owner ran every classic dungeon and raid manually (complete 2026-11-19, zero server errors),
then continued the manual sweep into TBC on 2026-11-20 with solo cheated runs: 7 of 16 TBC dungeons
(Auchenai Crypts, Blood Furnace, Hellfire Ramparts, Mana-Tombs, Sethekk Halls, Shadow Labyrinth,
Shattered Halls) — zero findings, zero server errors across the whole day. The owner then decided to
stop the manual sweep: the sampled content all works, and continuing instance-by-instance adds
little over letting real play find the outliers.

## Decision

1. The manual instance sweep ends on 2026-11-20. The record stays in
   `runbook/audits/2026-11-19-manual-instance-runs.md`.
2. All remaining unvisited TBC and WotLK dungeons and raids are **assumed functioning**. They are not
   pre-verified before launch.
3. Coverage for the remaining content is player-report-driven: a player ticket or bug report on an
   instance triggers verification of that instance — a manual run first, and a bot-rig replay
   (`mod-dungeon-clear`) when a reproducible defect needs one, per
   [ADR-016](ADR-016-bot-driven-verification.md) and [ADR-017](ADR-017-bot-rig-paused.md).
4. The Phase 1 exit gate in [ADR-013](ADR-013-server-and-client-before-website.md) is read with this
   deviation: instance coverage is classic-complete + 7 sampled TBC dungeons + the standing
   zero-error record, not a full TBC/WotLK sweep. The deviation is recorded here instead of
   rewriting the accepted ADR.
5. The Phase 1 gate itself still requires the other measured items to hold (stability, GM tools,
   documentation, verification gates).

## Consequences

- Outlier bugs surface during play, not before launch; the ticket/bug-report loop
  ([runbook/operation/bug-reports.md](../runbook/operation/bug-reports.md)) is the safety net.
- Ony's Lair (the level-80 rework) stays open from the 2026-11-19 record and is verified on a player
  report like the rest.
- The bot rig remains the reproduction tool for report-driven replays, paused otherwise.

## References

- [ADR-013](ADR-013-server-and-client-before-website.md)
- [ADR-016](ADR-016-bot-driven-verification.md)
- [ADR-017](ADR-017-bot-rig-paused.md)
- [runbook/audits/2026-11-19-manual-instance-runs.md](../runbook/audits/2026-11-19-manual-instance-runs.md)
