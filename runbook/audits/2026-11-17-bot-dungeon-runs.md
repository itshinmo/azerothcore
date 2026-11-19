# Bot dungeon runs — tracking ledger

Runs start only on the repository owner's explicit go, in gated batches: classic dungeons, TBC
dungeons, WotLK dungeons, classic raids, then TBC raids. Each finished run is reported and added
here. Deadmines and Shadowfang Keep were already green before the sweep and are not repeated. The
table summarizes each run; the exact `TESTRUN START`/`END` lines live in the rig log
(`~/wow/playerbot-rig/logs/worldserver.log`) keyed by run id and seed — the seed makes a run exactly
replayable with `.dc test start <dungeon> seed=N`. Failures become findings in the
[checklist](../operation/base-game-verification.md) results or `data/sql` fixes.

## Scope change (2026-11-19)

Dungeons are assumed to work. The classic sweep below is the record, and the TBC and WotLK 5-man
batches are cancelled by the owner. A player report is now the trigger to run a dungeon again; the
rig keeps its data, traces, and this ledger for that. Policy:
[ADR-016](../../decisions/ADR-016-bot-driven-verification.md). Raid batches were launched on
2026-11-19 and then paused by [ADR-017](../../decisions/ADR-017-bot-rig-paused.md); their results are
historical.

## Sweep plan (2026-11-18)

- Classic 5-mans: 27 tokens, including all four Maraudon tokens, plan `tp-20261118-160918-1`, four
  parties concurrent (later raised to 5, then 7, then 8), bag pick so every dungeon runs exactly once.
- TBC 5-mans: 16 tokens, same form, on the owner's go. **Cancelled 2026-11-19** (dungeons assumed
  green; ADR-016).
- WotLK 5-mans: 16 tokens, same form, on the owner's go. **Cancelled 2026-11-19** (dungeons assumed
  green; ADR-016). The registry has no WotLK raid entries.
- Classic raids: `mc, bwl, zg, aq20, aq40, ony`, two parties concurrent. **Launched 2026-11-19,
  then paused (ADR-017).**
- TBC raids: `gruul, kara, kara-chess`, two parties concurrent; `kara-chess` is a scenario slice of
  Karazhan and counts as its own token. **Launched 2026-11-19, then paused (ADR-017).**
- Pool plans launch raids at the catalogue default of 10 bots. A raid that fails there gets one
  rerun at its map cap before a finding is filed: 40 for `mc`, `bwl`, `aq40`; 20 for `zg`, `aq20`;
  25 for `gruul`; 10 for `ony`, `kara`, `kara-chess`. The paused batches never reached the reruns.
- Measured batches are watched with the camera only. A GM body enters an instance only on
  throwaway runs, because a nearby real player can change bot behavior.

## Raid batches (2026-11-19)

Classic raids: `mc, bwl, zg, aq20, aq40, ony`, two parties concurrent. TBC raids: `gruul, kara,
kara-chess`, two parties concurrent; `kara-chess` is a scenario slice of Karazhan and counts as its
own token. Both batches launch at the catalogue default of 10 bots; a failed raid is rerun once at
its map cap before a finding is filed: 40 for `mc`, `bwl`, `aq40`; 20 for `zg`, `aq20`; 25 for
`gruul`; 10 for `ony`, `kara`, `kara-chess`. The pause stopped the batches before any rerun.

Rig config change for this batch: `DungeonClear.TestRun.OverallTimeoutS` raised 7200 → 21600, because
a 10-bot classic raid can exceed two hours. Config backup:
`env/dist/etc/modules/mod_dungeon_clear.conf.pre-raid`.

Plan `tp-20261119-132403-1` (classic raids) launched 2026-11-19; it recorded the `ony` and `mc`
wipes, then `aq20` and `aq40` were aborted by the speed-mode restart and left no records. Plan
`tp-20261119-134727-1` relaunched the classic pool under speed mode.

### Speed mode (2026-11-19)

To fit every raid token into one session the rig now runs weakened creatures:
`Rate.Creature.*.HP = 0.2` and `Rate.Creature.*.Damage` / `.SpellDamage = 0.5` in
`env/dist/etc/worldserver.conf` (backup `worldserver.conf.pre-raid-speed`). A 10-bot raid against
25–40-player content otherwise wipes on trash. The run proves the party can start, progress, and
finish without errors; it does not judge combat tuning. Rows 1–2 ran before this change; later rows
use it. A finding counts only if it survives a replay under the same settings.

| # | Date | Run id | Raid | Seed | Result | Bosses | Duration | Notes |
|---|------|--------|------|------|--------|--------|----------|-------|
| 1 | 2026-11-19 | tr-20261119-132408-2 | `ony` | 2269105357 | wipe | 0/1 | 653s | Party wiped to trash: Onyxian Whelp (entry 11262), last standing Yolana. Pre-speed-mode. Rerun cancelled (ADR-017). |
| 2 | 2026-11-19 | tr-20261119-133501-3 | `mc` | 690188609 | wipe | 0/11 | 164s | Party wiped to trash: Lava Spawn (entry 12265), last standing Jaltraa. Pre-speed-mode. Rerun cancelled (ADR-017). |

### Plan interruption (2026-11-19 14:08)

Plan `tp-20261119-134727-1` stopped when the rig worldserver process disappeared about 21 minutes
in (`mc` 3/11, `aq20` 3/6). No shutdown lines and no crash report were written, which points at a
SIGKILL under host memory pressure: 16 GB RAM, ~60 MB free pages, Valheim plus three Firefox
instances running. The partial runs left no records. Resume only on the owner's explicit request
(ADR-017); the host-pressure cause is not a content finding.

## Pause (2026-11-19)

The rig is paused on the owner's decision; see
[ADR-017](../../decisions/ADR-017-bot-rig-paused.md). No process runs. The databases, worktree,
traces, rollback binaries, and this ledger stay for a future resume. The owner tests content
manually in the meantime, and bot results below remain historical, not coverage.

## Classic batch result (2026-11-18)

Plan `tp-20261118-160918-1` finished `runs=27/27 ok=24 fail=3`, total wall time 11,452s (~3h11m).
Average run 1,834s per the plan record. Every classic 5-man token has now been attempted at least once.

| # | Date | Run id | Dungeon | Seed | Result | Bosses | Duration | Notes |
|---|------|--------|---------|------|--------|--------|----------|-------|
| 1 | 2026-11-17 | tr-20261117-231354-1 | `deadmines` | 259986023 | success | 8/8 | 2057s | Smoke test. Freeze detector fired at the Gilnid standoff and the run self-recovered. |
| 2 | 2026-11-18 | tr-20261118-001306-2 | `sfk` | 4092029173 | success | 8/8 | 1261s | No freeze events. |
| 3 | 2026-11-18 | tr-20261118-160923-1 | `sm-cath` | 3113833077 | success | 2/2 | 825s | First run of the classic batch. |
| 4 | 2026-11-18 | tr-20261118-160923-2 | `stockade` | 3217307551 | success | 5/5 | 1073s | |
| 5 | 2026-11-18 | tr-20261118-160923-4 | `scholo` | 293760529 | success | 11/11 | 2507s | |
| 6 | 2026-11-18 | tr-20261118-160923-3 | `lbrs` | 1709499411 | no_progress | 7/7 | 4075s | F1. Replay succeeded after the harness fix. |
| 7 | 2026-11-18 | tr-20261118-162308-5 | `rfk` | 2451708861 | success | 6/6 | 1982s | |
| 8 | 2026-11-18 | tr-20261118-162716-6 | `strat` | 4292897129 | success | 13/13 | 4003s | |
| 9 | 2026-11-18 | tr-20261118-165017-7 | `mara-pw` | 4045238629 | success | 3/3 | 1806s | |
| 10 | 2026-11-18 | tr-20261118-165110-8 | `brd-db` | 893363673 | no_progress | 3/9 | 1568s | F2. Replay succeeded after the harness fix. |
| 11 | 2026-11-18 | tr-20261118-165610-9 | `ubrs` | 2506374811 | success | 8/8 | 2345s | |
| 12 | 2026-11-18 | tr-20261118-171718-10 | `rfc` | 3899030165 | success | 4/4 | 1213s | |
| 13 | 2026-11-18 | tr-20261118-171718-11 | `bfd` | 3150551725 | no_progress | 8/10 | 3013s | F3. Fires objective stalled 0.4yd from the anchor; three replays below. |
| 14 | 2026-11-18 | tr-20261118-172400-12 | `sm-gy` | 789333571 | success | 2/2 | 463s | Fastest run of the batch. |
| 15 | 2026-11-18 | tr-20261118-173143-13 | `brd-uc` | 2781279525 | success | 17/17 | 2246s | |
| 16 | 2026-11-18 | tr-20261118-173359-14 | `uldaman` | 3969358701 | success | 9/9 | 1597s | |
| 17 | 2026-11-18 | tr-20261118-173515-15 | `maraudon` | 1366709661 | success | 7/7 | 4100s | Full Maraudon clear. |
| 18 | 2026-11-18 | tr-20261118-173731-16 | `wc` | 1924592909 | success | 11/11 | 2419s | |
| 19 | 2026-11-18 | tr-20261118-175217-18 | `zf` | 1909269715 | success | 7/7 | 1543s | |
| 20 | 2026-11-18 | tr-20261118-175217-17 | `mara-purple` | 1614897359 | success | 2/2 | 1582s | |
| 21 | 2026-11-18 | tr-20261118-180036-19 | `dm-north` | 2608611713 | success | 6/6 | 989s | |
| 22 | 2026-11-18 | tr-20261118-180413-20 | `sm-lib` | 1727090643 | success | 2/2 | 753s | |
| 23 | 2026-11-18 | tr-20261118-180731-21 | `rfd` | 314724645 | success | 4/4 | 1321s | |
| 24 | 2026-11-18 | tr-20261118-180909-22 | `mara-orange` | 2139428463 | success | 2/2 | 1473s | |
| 25 | 2026-11-18 | tr-20261118-181646-23 | `dm-west` | 185714619 | success | 18/18 | 1979s | |
| 26 | 2026-11-18 | tr-20261118-181705-24 | `st` | 1269097145 | success | 21/21 | 3785s | |
| 27 | 2026-11-18 | tr-20261118-181750-25 | `dm-east` | 3893814257 | success | 5/5 | 1641s | |
| 28 | 2026-11-18 | tr-20261118-181800-26 | `sm-arm` | 3774819645 | success | 1/1 | 694s | |
| 29 | 2026-11-18 | tr-20261118-181839-27 | `gnomer` | 4089829003 | success | 4/4 | 1696s | |

## Failure replays (2026-11-18)

Same seeds, `trace=1`, on the patched rig. Traces live in
`~/wow/playerbot-rig/env/dist/bin/lab_traces/` and are large (16 MB to 880 MB).

| # | Run id | Dungeon | Seed | Result | Bosses | Duration | Outcome |
|---|--------|---------|------|--------|--------|----------|---------|
| 30 | tr-20261118-192652-1 | `brd-db` | 893363673 | success | 9/9 | 2321s | F2 fix confirmed. |
| 31 | tr-20261118-192659-2 | `bfd` | 3150551725 | stalled_timeout | 2/10 | 574s | F3a first symptom: swim passage. Fixed, see below. |
| 32 | tr-20261118-192718-3 | `lbrs` | 1709499411 | success | 7/7 | 3286s | F1 fix confirmed. |
| 33 | tr-20261118-203726-1 | `bfd` | 3150551725 | paused_timeout | 8/10 | 2210s | F3b: portal door false block. Fixed, see below. |
| 34 | tr-20261118-211939-1 | `bfd` | 3150551725 | aborted | 8/10 | 2221s | Stopped by hand after F3c/F3d livelock; see findings. |

Raid batches start only on the owner's explicit go. Dungeon batches are closed unless a player
report reopens one.

## How to read this table

- `result=success` = every boss died and the run ended cleanly (`TESTRUN END ... bosses=N/N`).
- A `FROZEN` line is the run's own watchdog: it fires when the party makes no progress for 300s.
  If the run still ends `success`, the party recovered; if it ends `fail`, the frozen position is
  the finding.
- `stalled_timeout` = the DungeonClear stall reason held for its grace; `paused_timeout` = the
  door-blocked pause held for 60s; `aborted` = a human stopped the run.
- Findings worth a fix get a row below with the creature entry, evidence, and the proposed fix.

## Findings

All fixes below are in the rig harness (`mod-dungeon-clear`, outside this repository). None is a
world-database or core-content fix.

### F1 — `lbrs` failed with 7/7 bosses credited (`tr-20261118-160923-3`) — FIXED

The party killed Overlord Wyrmthalak at t=3416, then spent 540s advancing with no next boss before
the all-cleared latch fired, held loot for its 60s cap, and lost to the 600s no-progress watchdog on
the same tick. `completedEncounterMask` was `0x1EF` (bit 4, Urok Doomhowl, absent: a gameobject summon
not on the tested roster), and the run still counted 7/7 because `bossesTotal` excludes the two
non-spawning bosses.

Fix: the no-progress clock is held once `bossesKilled >= bossesTotal`, so the final-loot hold can
never lose the race to the watchdog. Confirmed by replay `tr-20261118-192718-3` (success 7/7).

### F2 — `brd-db` stopped en route to the Ring of Law (`tr-20261118-165110-8`) — FIXED

3/9 bosses, then the tank sat 60.4 yards from the Ring of Law anchor while the party cleared
Anvilrage packs. The no-progress sample read the tank only; a ranged pack on the healer or a DPS
pull is invisible to it.

Fix: the combat-progress sample folds every party member's combat flag, victim and victim health
into one change hash. A frozen fight still reads as no change. Confirmed by replay
`tr-20261118-192652-1` (success 9/9).

### F3 — `bfd` has four separate defects (two fixed, two open) — OPEN

`tr-20261118-171718-11` failed `no_progress` at 8/10 with the tank 0.4 yd from the fires anchor.
The three BFD replays isolated four independent problems.

**F3a — swim passage abandoned on entry drift (`tr-20261118-192659-2`, 2/10).** The leader entered
the authored swim chain at `(-381.2, 288.2, -57.3)` but the polyline's point 2 sits at
`(-362, 300, -66)`; the party stood at `z=-73.7`, 53 yd off, which trips `DcRawPathDrive`'s
`offLegMax = 50`. The step returned `OffLeg`, the chain abandoned, and it re-started every tick.
`Nythanna uwSec=161` — underwater 161s, never swimming.

Fix: on an `OffLeg` verdict **on a swim step**, `DcRawPathDrive` no longer abandons. It asks
`SwimPathfinder` to rebuild from the live position to the step's end, adopts that line, and drives it
with the same watchdog. Gated on `SwimPathfinder::WaterBetween`, so a real teleport still abandons.
Confirmed: the next replay got past both swim legs and Sarevess.

**F3b — Portal of Aku'mai read as a closed corridor door (`tr-20261118-203726-1`, 8/10).** After the
first fire the tank transited the portal doorway toward the next fire. The portal opens only after
all four fires and every wave summon is dead, so the blocking-door scan flagged it, the open attempt
was refused, and the run auto-paused 47 yd from the fires:

```
blocking-door: flagged ... 'Portal of Aku'Mai' (entry 21117) ... as corridor-blocking
door-blocked: can't open ... -> auto-pausing
```

Fix: `21117` was already `IsScriptOnly` (never click it) and is now also `IsNavigationIgnored` —
never flagged as a corridor blocker, never a reason to pause. Same rule as Thrall's prison door,
Chromaggus' portcullis, and the Violet Hold cells. Confirmed: no blocking-door or auto-pause in the
next replay.

**F3c — advance/objective livelock on an empty path (`tr-20261118-211939-1`, 8/10) — OPEN.** Standing
on the fires anchor, `DcAdvanceAction` rebuilt an empty path every tick and forced another rebuild:

```
path rebuilt -> Light the Fires of Aku'mai (async): segs=0 firstSegPts=0 complete=true
reached end of path polyline (seg 0) -> forcing rebuild next tick
```

4,003 identical lines. The advance rung owns the tick, so the objective event never runs. The
livelock burns CPU (worldserver 47%) and blocks the last fire.

**F3d — wave gate starvation (`tr-20261118-211939-1`) — OPEN.** After the third fire the next step
is `KillCreatureEngage(Barbed Crustacean, 1, 90yd)`. The wave was alive at 33–73 yd, yet the party
stood out of combat on the anchor at full HP/mana, so the gate never cleared and
`Use GO 21121` (the fourth fire) was never reached.

Three of four fires were confirmed lit (`21118`, `21119`, `21120`).

Open work for the next session: yield the tick to the objective action when the path to the anchor is
empty, and make the wave gate pull its creatures instead of waiting. Then replay seed `3150551725`
again.

## Harness changes made during this sweep

All in `~/wow/playerbot-rig/core/modules/mod-dungeon-clear`, built into the rig only:

1. `TestRun/DcTestRunJob.cpp` — no-progress clock held once `bossesKilled >= bossesTotal` (F1).
2. `TestRun/DcTestRunJob.cpp` + `.h` — party-wide combat-progress hash (F2).
3. `Util/DcPartyWideChain.cpp` + `.h` — swim replan through `SwimPathfinder` on `OffLeg` (F3a).
4. `Data/DcEventDoorRegistry.h` — Portal of Aku'mai `21117` added to `IsNavigationIgnored` (F3b).

Rig binaries kept for rollback: `env/dist/bin/worldserver.pre-20261118` and
`env/dist/bin/worldserver.pre-swimfix`.
