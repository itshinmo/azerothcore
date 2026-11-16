# Base-game verification checklist

Phase 1 exit criterion: the base game works and stays up while a player levels, dungeons, trades,
and travels. This checklist turns that into playable sessions. Work through it in order; skip
nothing silently — record every failure in a results file (see [Recording results](#recording-results)).

Data snapshot used for scope (2026-11-16, `acore_world`): 9,464 quests, 2,956 quest-chain links,
53,821 SmartAI rows, 1,851 C++ scripted creature templates. The content audit
([2026-11-14](../audits/2026-11-14-content-audit.md)) covers data-level consistency; this checklist
covers what a player actually experiences.

## Before each session

1. `make status` — both servers up, GM API bound. `make doctor` if anything looks off.
2. `make backup` — the session may create characters and items you later want to roll back.
3. Log in with the player account (`TESTPLAYER`, no GM mode) for gameplay checks; use the `ADMIN`
   client only for GM assistance (teleport, `.additem` of test gear).
4. Keep `make logs` open in a second terminal; note anything red as you play.

## A. New-character flow

Run once per faction (Alliance and Horde), once per expansion bracket if time allows.

- [ ] Character creation and first login for both factions.
- [ ] Starting zone: intro quests complete; class starter quests work.
- [ ] Trainer: spells train and cost money; auto-learn on level-up where applicable.
- [ ] Talent panel opens; spending a point applies the effect.
- [ ] First profession learned; skill increases on use; trainer teaches recipes.
- [ ] Death: corpse run works, spirit healer resurrects, durability damage appears.
- [ ] Level 10+: class-specific mechanic appears (pet for hunters/warlocks, stance/bar for
      warriors/rogues/ferals, etc.).
- [ ] First mount at the right level, trained and usable; riding skill enforced.

## B. Leveling path (realm rate 2x, ADR-012)

Expected pace: roughly 70-90 hours to 80. Test each band in one sitting; complete at least one full
zone quest arc per band, not just kills.

- [ ] 1-10: starting zone arc end-to-end (e.g. Elwynn / Durotar / Teldrassil).
- [ ] 10-20: second zone arc (Westfall / Silverpine / Loch Modan); one elite quest done in a group.
- [ ] 20-40: one classic zone arc (Ashenvale / Hillsbrad / STV segment); first dungeon run
      (Deadmines or Wailing Caverns) with the group finder.
- [ ] 40-60: pre-60 quest arc (Tanaris / Feralas / Hinterlands); second dungeon tier (e.g. ZF, Uldaman).
- [ ] 58-70: Hellfire Peninsula opening arc; an Outland dungeon (e.g. Botanica or Shadow Labyrinth).
- [ ] 68-80: Borean Tundra or Howling Fjord arc; a Northrend dungeon (e.g. Nexus or Utgarde Keep).
- [ ] Quest chain integrity: pick three chains in different bands, complete start to end. 2,956
      chain links exist; a broken link means the next quest never appears — record the chain.

## C. Dungeons and raids

The dungeon content runs on SmartAI (hundreds to thousands of rows per map) plus C++ scripts.
Test one dungeon per tier in a full group; for each:

- [ ] Trash pulls behave (aggro radius, leash, pack mechanics).
- [ ] Each boss: engaged with the script path active (pull, special ability, kill). Bosses that do
      nothing special are findings — that is what we are looking for.
- [ ] Loot: boss drops appear, group loot rolls work, chest loot works.
- [ ] Reset: leaving and re-entering resets trash; instance lock persists per rules.
- [ ] Raid spot-check (one raid, one boss wing): e.g. Naxxramas construct wing or Onyxia.

Record the map id of any problem (`.gps` shows it) so the audit can trace the creature.

## D. Systems

- [ ] Mail: send, receive, COD, item attachment, expiry refund.
- [ ] Auction house: bid, buyout, sell, mail payout; deposit cut shown.
- [ ] Bank: deposit/withdraw, bag slots.
- [ ] Guild: create, charter, bank tab, repair funds.
- [ ] Battleground: queue, enter, complete one match (WSG or AB), marks and rewards.
- [ ] Dungeon finder: queue as tank/dps, teleported in, teleported out after.
- [ ] Hearthstone and homebind: set inn, use stone; unstuck API already tested.
- [ ] Flight paths: learn, ride, intercontinental route (boat/zeppelin/portal).
- [ ] Vendor: buy, sell, limited-stock item refresh; repair.
- [ ] Pets and mounts from quest items; stable for hunters.

## E. Client-observed behavior

- [ ] Movement, collision, and swimming in a river (known water issue lives in
      [stormwind-water.md](../troubleshooting/stormwind-water.md) — re-check that it stays
      client-side only).
- [ ] Combat feel: swings, casts, resists, dodges visible and consistent on both players and mobs.
- [ ] Loot window, bag stacking, item tooltips.
- [ ] Sound and music load per zone; no silence storm after teleports.
- [ ] Map and minimap: zone names, flight arrows, coordinates on `.gps` match the client map.
- [ ] Addon compatibility: GM Helper addon still works after a full session (no Lua errors).

## F. Stability

- [ ] Soak: server up through a full session (2+ hours) with a player online; memory stable in
      `make status` snapshots.
- [ ] Restart cycle: `make stop`/`make start` clean; watch the SIGTERM 30s SIGKILL delay seen on
      2026-11-16 — if it repeats, capture `make logs` before stopping.
- [ ] GM API regression: run the Bruno collection safe set after the session; all reads `200`.
- [ ] Crash capture: if worldserver dies, do NOT restart first — run the lldb recipe:
      `cd env/dist/bin && lldb -b -o run -k 'bt all' -k 'quit' -- ./worldserver > /tmp/crash.log 2>&1`,
      reproduce, and send the backtrace. AC has no POSIX crash handler, so the debugger is the only
      artifact source (see the 2026-11-16 `.xp` crash that left no trace).

## Known-issue watchlist

- `libSiliconPatch` stays off until WoWSilicon#67 closes; keep the second client copy without mods.
- Test realm death log capture (supervisor log) on next occurrence.
- 16 remaining C-06 phase-reachability findings from the content audit — consult when a phase
  script misbehaves in the field.

## Recording results

Create `runbook/audits/<date>-base-game-playtest.md` per session with:

1. Which sections were played and which items passed/failed.
2. For each failure: character, location (`.gps`), what was expected vs observed, and the relevant
   log excerpt.
3. Findings get triaged after the session: data fix (SQL update), code fix (module/core), or
   accepted with a waiver in the content audit.

The checklist above is the master copy; do not edit it during a session — copy the items into the
results file and check them there.
