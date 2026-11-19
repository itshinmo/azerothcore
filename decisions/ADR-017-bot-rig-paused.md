# ADR-017 — Bot rig paused; manual verification is the current content check

- Status: accepted
- Date: 2026-11-19
- Amends: [ADR-016](ADR-016-bot-driven-verification.md)

## Context

The classic and TBC raid batches started on 2026-11-19. Pre-speed-mode runs wiped on trash
(`ony` 0/1, `mc` 0/11); the rig then ran with `Rate.Creature.*.HP = 0.2` and creature damage at 0.5.
The second classic plan reached `mc` 3/11 and `aq20` 3/6 when the worldserver disappeared at 14:08.
No shutdown lines and no crash report were written. The host had 16 GB RAM and about 60 MB of free
pages with a game running, so the process was likely killed under memory pressure.

The owner has decided to test all content personally from now on. The bot rig has no owner for its
remaining batches.

## Decision

1. The bot rig is paused from 2026-11-19. No rig process runs.
2. Its data, traces, ledger, worktree, and binaries are kept. They are the reproduction material if
   bot work resumes.
3. Manual verification by the owner is the current content check for dungeons and raids. The agent
   correlates server logs and files or fixes findings reported by the owner.
4. Bot work does not resume without an explicit owner request. Until then, the rig results are
   historical and do not count as coverage.
5. The Phase 1 exit gate in [ADR-013](ADR-013-server-and-client-before-website.md) still names a bot
   dungeon pool. Until the rig resumes, that gate is read as manual verification of the same content
   plus report-driven replay. The deviation is recorded here instead of rewriting the accepted ADR.

## Consequences

- Raid coverage is incomplete by bot: `ony` and `mc` have pre-speed-mode wipes; the rest are untested
  by bots.
- The rig stays as dormant infrastructure; nothing is deleted.
- Verification load moves to the owner, with agent support for triage and fixes.

## References

- [ADR-015](ADR-015-playerbot-test-rig.md)
- [ADR-016](ADR-016-bot-driven-verification.md)
- [runbook/operation/playerbot-rig.md](../runbook/operation/playerbot-rig.md)
- [runbook/audits/2026-11-17-bot-dungeon-runs.md](../runbook/audits/2026-11-17-bot-dungeon-runs.md)
