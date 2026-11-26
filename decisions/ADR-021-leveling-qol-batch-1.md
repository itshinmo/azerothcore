# ADR-021 — Leveling QoL batch 1 (auto-learn class spells, cheap dual spec)

- Status: accepted; revised 2026-11-26 — clause 1 (auto-learn class spells) superseded and the
  module removed, trainers are the sole spell source; clauses 2 and 3 stand
- Date: 2026-11-20, revised 2026-11-26
- Implements: [RFC-003](../rfcs/active/RFC-003-qol-social-slate.md) Group A (owner decisions of 2026-11-20)

## Decision

1. **Auto-learn class spells** — new local module `modules/mod-auto-learn-spells`
   (PlayerScript on `OnPlayerLogin` + `OnPlayerLevelChanged`): every spell the player's
   class trainers would sell at the current level is learned automatically, free, Cataclysm-style.
   The learned set is driven by the server's `trainer`/`trainer_spell` data through the core
   `Trainer` availability filter (`Trainer::CanTeachSpell`), the exact logic the trainer UI uses,
   so there is no hand-maintained spell list. Mount, pet and tradeskill trainers are untouched;
   talents stay talent-point purchases; the trainer NPC UI stays as-is (players may still use it).
   Every login doubles as a cheap catch-up pass for pre-existing characters (known spells are
   skipped by the filter). LEARN_SPELL wrapper entries (class mounts, druid flight forms) are
   taught the way the trainer itself teaches them — by casting the wrapper — which keeps their
   own gating (Riding skill for class mounts and flight forms) and their bundled side effects.
   No config: disabling goes through `DISABLED_AC_MODULES`.
   Shamans additionally receive their four totem items (5175-5178) on login when missing —
   their totem spells are gated on `TotemCategory` in Spell.dbc (core checks the bags) and
   retail grants these items via the level 4/10/20/30 class quests; only shamans have such
   item-gated abilities in the trainer data (audit across all classes, 2026-11-21).
   Deliberately not vendored from `azerothcore/mod-learn-spells`: that module is a heuristic
   spell-family scan with a hand-maintained ignore list whose own tracker reports bugged/invalid
   learns (issues #50, #56, open 2026-11-20); our filter reuses core-owned data instead.

   **SUPERSEDED 2026-11-26 — the module is removed; trainers are the sole spell source again.
   See [Revision 2026-11-26](#revision-2026-11-26--auto-learn-class-spells-withdrawn) below.**

   **Revision 2026-11-21 — transmog collection rules (owner decisions):** appearances now
   collect on soulbound items only at pickup; unbound (BoE) items unlock on **equip** or on the
   new **Ctrl+right-click** action (addon → `CollectItem` server handler), which collects **and
   soulbinds** the item (Ascension's mechanic) — so a traded BoE never counts for its giver,
   and collecting commits the item. Equipping also soulbinds the item (an equipped look can
   never be traded for its appearance afterwards). Login scans go bound-only. History is not
   purged. The `Transmog.Collect.OnPickup` config keeps the same key with the new bound-only
   semantics.
   **Backpacks removed** from the module and the addon entirely (server file, config, tables —
   the world-side table and unlock item 27621 in `data/sql/world/`, the three characters-side
   tables in `data/sql/db-characters/` — plus the addon tab; the client models were already
   absent after patch-S came off).
2. **Dual spec at level 30, free** (owner decision 2026-11-20): `MinDualSpecLevel = 30` in
   `worldserver.conf.dist` (fork default) and the live `env/dist/etc/worldserver.conf`. Verified
   before deciding: this core's dual-spec learn (trainer gossip casting spells 63680/63624) and
   spec switching cost nothing, so "cheap" is satisfied on cost and the level gate is the only knob.
   Retail parity minus the 10 gold.
3. **Auto flight paths dropped** (owner decision 2026-11-20, amending RFC-003 Group A): players
   must discover flight paths. The core `AllFlightPaths` config stays off (upstream default).
   If this ever returns, the config is the zero-code path and should be revisited then.

## Tests and verification

**Superseded 2026-11-26 for the auto-learn items (T3 rows 1-3): the module no longer exists, so
those checks cannot be run.** The skill-related rows still describe stock trainer behaviour.

- `make build` compiles the module into the worldserver; no SQL, no config schema changes.
- Unit tests: none — the module is a thin loop over core-owned data and the core-owned
  availability filter; the meaningful checks are behavioral (T3 below).
- T3 manual checklist (owner in game):
  1. A character below 30 levels up → new class spells appear without visiting a trainer
     (spot-check a rank gained at that level; the spellbook shows it).
  2. A pre-existing character logs in once after the module lands → catch-up learns any
     trainer spells its level allows but it had not bought (the login pass).
  3. Level 30 character talks to a class trainer → "Learn dual spec" offered; learning and
     switching cost nothing; a level-29 character is not offered it.
  4. Spell ranks respect prerequisites (e.g. no rank-3 without rank-2) — automatic, since the
     filter is the trainer UI's, but spot-check one chain.
  5. Wrapper-taught spells still need the trainer visit: a druid's Flight Form and a warlock's
     Felsteed are not auto-learned (they are cast by the trainer and carry side effects).
- Failure mode to watch: a spell missing from `trainer_spell` for a class trainer is simply
  never auto-learned — same spell stays purchasable from the trainer, so gaps surface as
  normal trainer visits, not as broken characters.

## Revision 2026-11-26 — auto-learn class spells withdrawn

**Clause 1 is superseded; clauses 2 and 3 stand.** `modules/mod-auto-learn-spells` is deleted
(module, README, both files in git history only). Auto-learn removed a layer of transaction:
a spell had no price and no trainer visit, so nothing in the leveling path asked a player to
walk into town. The class-trainer summon that is planned as a shop convenience depends on that
transaction — the trainer must sell spells for the convenience to be worth anything — so
trainers are the sole spell source again.

What changes for players:

- **Class spells are bought from class trainers again** at their normal price, level and
  prerequisite gates. The stock trainer data is untouched.
- **No more shaman totem grant.** The module also handed Earth/Fire/Water/Air Totem
  (5175-5178) to every shaman on login, which the totem spells' `TotemCategory` requirement
  needs. That grant is gone with the module; the owner chose "restore the stock totem quests"
  instead of moving the grant elsewhere.

Shaman totem audit (base data, read-only, 2026-11-26). Each of the four totems is a quest
reward in `data/sql/base/db_world/quest_template.sql` (RewardItem1, amount 1):

- **Earth Totem (5175)** — three parallel `Call of Earth` chains, all reward 5175, all shaman
  class mask 64:
  - Orc/Troll (mask 130): 1516 -> 1517 -> 1518; started and ended by Canaga Earthcaller
    (5887), Valley of Trials, with the Minor Manifestation of Earth (5891) as the middle
    giver. Both creatures spawn.
  - Tauren (mask 32): 1519 -> 1520 -> 1521; started and ended by Seer Ravenfeather (5888),
    Camp Narache, with the Minor Manifestation of Earth (5891) in the middle. Both spawn.
  - Draenei (mask 1101): 9449 -> 9450 -> 9451. 9449 starts at Firmanvaar (17089) and ends at
    Spirit of the Vale (17087); 9450 and 9451 start at 17087, and 9451 ends at 17089. Both
    spawned once. (An earlier draft had the start and end reversed; corrected 2026-11-26.)
- **Fire Totem (5176)** — two paths:
  - Horde: 1524 -> 1525 -> 1526 -> 1527; starter Brazier of the Dormant Flame gameobject
    (61934, one spawn), ender Kranal Fiss (5907, spawned once). Breadcrumbs 1522/1523 from
    Searn Firewarder (5892) and Beram Skychaser (3032).
  - Draenei: 9461 (from Tuluun, 17212) -> 9555 (from Prophet Velen, 17468; ends at Farseer
    Nobundo, 17204). Breadcrumbs 9462-9468 lead in; every creature spawns once.
- **Water Totem (5177)** — two paths:
  - Horde: 1528/1529 -> 1530 -> 1535 -> 1536 -> 1534 -> 220 -> 63 -> 100 -> 96; starter Islen
    Waterseer (5901, spawned once), ender Islen Waterseer. Quest 63 is finished at the Brazier
    of Everfount gameobject (113791, one spawn), whose SmartAI summons Minor Manifestation of
    Water (5895); that summoned creature ends 100 and starts 96. Quest 96 rewards the totem.
  - Draenei: 9500 (from Sulaa, 17219) -> 9501 -> 9503 -> 9504 -> 9508 -> 9509, run through
    Aqueous (17275) and ended at Farseer Nobundo (17204). Every creature spawns once.
- **Air Totem (5178)** — two paths:
  - Horde: 1531 (starter Searn Firewarder 5892) and 1532 (starter Xanis Flameweaver 5906), both
    ending at Prate Cloudseer (5905). All three creatures spawn once; the two quests are
    alternatives in the same exclusive group, and each rewards 5178.
  - Draenei: 9547 -> 9552 -> 9553 -> 9554; starter Farseer Javad (23127), ender Farseer Nobundo
    (17204), both spawned once.

The arrows follow `PrevQuestID` in `quest_template_addon` (chain order top-down), not
`RewardNextQuest`: quest 220 has `RewardNextQuest = 0` and is linked only through
`PrevQuestID`. That is why the water chain reads longer than its reward-next links.

All four totems are obtainable: **no blocker.** Notes from the audit:

- Every quest in the set carries `AllowableClasses = 64` (shaman) in `quest_template_addon`, and
  none is disabled in `disables.sql`.
- The summoned-creature steps are intended, not data gaps: the water manifestation exists only
  as a SmartAI summon from the brazier, and the fire turn-in is at a spawned gameobject.
- **No totem is vendor-sold.** `npc_vendor` has no row for item 5175, 5176, 5177 or 5178. The
  `5175` and `5178` entries that turned up in an earlier pass are creature entries in
  `creature_template` (Gearcutter Cogspinner, Soolie Berryfizz), not items, so the earlier claim
  that Earth and Air were also purchasable was wrong (corrected 2026-11-26). All four totems are
  quest-only, so every chain above must work for its race. They are intact and shaman-only.

**Grandfathering.** The module only ever added things: `learnSpell` and `AddItem`, never a marker,
config row or database row. Removing it therefore cannot invalidate a saved character. A character
keeps every spell and totem it already has and simply pays for the next rank at the trainer, which
is the intended effect. The one sharp edge: a shaman who deletes a totem item cannot re-earn it,
because the four chains are non-repeatable and shaman-only, and no vendor sells any of the four. A
replacement grant is deliberately not added; if that edge bites in play, it belongs in the future
shop convenience rather than in this module.

Unaffected by this revision: dual spec at level 30 free (clause 2) and auto flight paths staying
dropped (clause 3). No SQL is added or changed; the stock quests and trainer data carry the
behavior.
