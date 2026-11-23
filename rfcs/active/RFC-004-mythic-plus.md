# RFC-004 — Mythic+ for old content

- Status: discussion
- Date: 2026-11-23
- Author: implementation subagent (audit + proposal)
- Decision record: [ADR-034](../../decisions/ADR-034-mythic-plus-old-content.md) (proposed)
- Contract: §Contract (proposed) below
- Recommendation status: values marked **recommended, pending owner** are proposals, not decisions.
  They are tracked in [decisions/OPEN-QUESTIONS.md](../../decisions/OPEN-QUESTIONS.md).

## Problem

Level-80 characters have no reason to run Classic and TBC five-player dungeons. The instances are
trivial, their loot is below the level-80 budget, and the existing candidate module gives a timer and
affixes but no scaled reward. The owner wants a long-tail old-content ladder that is earned in play,
not sold.

The candidate is `silviu20092/mod-mythic-plus` (MIT). It is a useful timer/affix scaffold, but it is
not a complete old-content loot system. This RFC records the audit, the vendor/fork decision, the
raid gap, the proposed contract and the open questions. The contract lives in §Contract (proposed)
below until the owner accepts ADR-034.

## Candidate audit

Audited at commit `e2a487d` (2026-03-23), depth-50 clone. About 4,500 lines of C++20 plus 21 SQL
files. Our fork HEAD is `c345057a2` (2026-11-23). The module was not compiled against the fork; the
hook signatures and APIs it uses are present, but compile compatibility is a slice-1 gate.

**Licence.** MIT, copyright 2023 AzerothCore, author silviu20092. Vendoring and modification are
allowed with the licence and attribution.

**Supported AC.** Claims "latest acore" at `e2a487d`; CI uses `core_build_modules.yml@main` with no
pinned core commit. No compatibility matrix. Treat it as an unpinned target, not a guarantee.

**Hooks.** `AllMapScript` (enter/update/destroy), `AllCreatureScript` (`OnAllCreatureUpdate`),
`UnitScript` (damage/death/evade/update), `PlayerScript` (login/death), `GroupScript` (add member),
`WorldScript` (init/update/config), `CreatureScript` (gossip), `ItemScript` (keystone),
`CommandScript`. The newer hook-list constructor style is used.

**SQL.** `DROP TABLE` + `CREATE` in module SQL, outside the house re-applicable custom-SQL
convention. IDs `70001`, `200005` and `200006` are outside the house ranges.
`mythic_plus_dungeon_snapshot` has no primary key or index. No foreign keys.

**Dungeon pool.** 14 rows: 12 WotLK dungeons plus Ragefire Chasm and Razorfen Kraul. No TBC
dungeon, no Culling of Stratholme, Violet Hold, Trial of the Champion or Halls of Reflection. "Old
content" is much narrower than the label suggests.

**Final boss data.** Ragefire Chasm uses 11519 (Bazzalan) instead of 11520 (Taragaman the
Hungerer). Final-boss detection is a global entry scan, so a reused entry can complete the wrong
map. Data needs a validated boss table.

**Raids.** Not supported; see the gap list below.

**Keystone.** Item 70001, unique, bind-on-pickup, purchased from the NPC with a default 24-hour
cooldown. Group leader only; 10-second delay; all group members must be online and level 80. One
global character key level, not per-era or per-dungeon. The proposed design uses no key item.

**Affixes.** Nine affix types (health, trash/boss health, multiple enemies, damage, explode,
lightning sphere, enrage, roots). Key levels 1–5 only. No key-level creature scaling; difficulty
comes from stacking affixes. Random affixes are re-rolled on every server restart;
`Utils::RandomEngine()` returns the static engine by value, so the state never advances and the
"random" pick is reproducible. No seasonal affix.

**Timer.** Per-level 40–45 minutes in SQL. Starts ten seconds after the key is used, not on first
pull. Death penalty 15 seconds. Uses wall-clock Unix time, so server downtime counts against the
run. No restart-abandon policy.

**Standings.** Per-player, per-boss snapshot rows. No primary key or index. Every ten minutes the
world update runs a full `GROUP_CONCAT` query over the whole table and rebuilds an in-memory copy.
Unbounded growth and a periodic full scan. `mapdifficulty` is parsed with `Get<bool>()`, so the
displayed difficulty is wrong.

**Loot.** None. Creature loot is untouched. Completion pays gold (1M–15M copper) plus Emblem of
Triumph 29434 and a keystone. `AddItem` return values are ignored, so a full bag loses the reward.
No currency, vendor, upgrade, recycle, weekly chest or scaled item.

**Lockouts.** No lockout model. One `mythic_plus_dungeon` row per instance ID, deleted on instance
destroy. The core five-instances-per-hour limit still applies. No raid lockout support.

**Performance.** `OnAllCreatureUpdate` runs for every creature; `OnUnitUpdate` runs for every unit
and iterates all affixes. Snapshots insert one row per player per boss kill. `GetMapSnapshot` copies
the whole vector per gossip page. The gossip `playerPagedData` map is never erased on logout, so
each player who opens the NPC leaves an entry behind.

**Security.** SQL is built with `CharacterDatabase.Execute("... {} ...")` formatting, including a
quoted character name, instead of prepared statements. Commands use `SEC_PLAYER`/`SEC_ADMINISTRATOR`
without module RBAC permission rows; the core command audit may log the call, but the module adds no
audit rows. Several `ASSERT`s on missing saved-dungeon data can abort the worldserver on inconsistent
state. No rate limit on gossip pages or keystone purchase beyond the buy timer.

**Code quality.** Readable and consistent, modern C++20, clear separation of affix classes.
Weaknesses: raw `new`/`delete` ownership, no unit tests, hardcoded English strings and IDs, no
localization for gossip text, `ASSERT` in runtime paths, `StoreOriginalCreatureData` runs after
`ScaleCreature` so health affixes stack on already-scaled health, and the bugs above.

**AutoBalance.** Both modules hook `OnAllCreatureUpdate` and scale the same creature. Load order
decides which scale wins; AutoBalance resets to its own "unmodified" values and can clobber the
Mythic+ scale. AutoBalance also scales money and XP. There is no integration or detection. Running
both on the same map is unsupported.

### What the module does well

- The run state machine is understandable: keystone, 10-second start, timer, death penalty, final
  boss, completion, saved instance row.
- Affixes have a clean polymorphic interface; the static and periodic effects are separated.
- The gossip paging helper, NPC skeleton and DB-backed level/affix/reward tables are a reasonable
  starting point.
- The code is MIT and small enough to refactor rather than replace.

### What it cannot do

- Generate or replace loot with scaled items.
- Give a per-era ladder, per-era progress or a key level that actually scales creature stats.
- Provide a coin currency, vendor, upgrade, recycle or weekly vault.
- Track runs without per-player, per-boss writes and a periodic full standings reload.
- Support raids.
- Coexist with AutoBalance without a clear owner of creature scaling.

## Raid gap (exact)

Raids need a fork or a separate module. The current code cannot be configured into raid support:

1. `CanBeMythicPlus()` and `MatchMythicPlusMapDiff()` require `MapEntry::IsNonRaidDungeon()`; raid
   maps are rejected before any other check.
2. `CanProcessCreature()` also requires `map->IsNonRaidDungeon()`; raid creatures are never scaled.
3. `LoadMythicPlusCapableDungeonsFromDB()` accepts only `DUNGEON_DIFFICULTY_NORMAL` and
   `DUNGEON_DIFFICULTY_HEROIC`; raid difficulties (`RAID_DIFFICULTY_10MAN_NORMAL`, 25-man, heroic)
   are rejected.
4. `mythic_plus_capable_dungeon` has `PRIMARY KEY (map)`, so one map cannot hold a 10-man and a
   25-man row with different final bosses or timers.
5. Completion is a single `final_boss_entry`; a raid needs all required encounters, not one entry.
6. There is no raid lockout integration: no `instance`/`character_instance` binding, no weekly reset,
   no per-boss state, no protection against re-entering a saved raid for a second reward.
7. Group checks assume a dungeon group: no 10/25 size validation, no raid composition, no
   difficulty-specific key rules.
8. Scaling hardcodes level 82 and five-player HP multipliers (`urand(20,21)` boss, `4` trash;
   `urand(30,31)`/`5` on heroic). Raid bosses need their own curve and encounter-aware scaling.
9. Loot replacement would need difficulty-specific raid loot tables and multi-boss distribution;
   the current reward path only pays money and a token at the final boss.
10. Raid IDs reset on a weekly schedule; the module's wall-clock timer and per-instance row have no
    concept of a raid week.
11. `IsDungeonBoss()` covers raid bosses, but the final-boss entry scan is global and would complete
    on a reused entry.
12. The candidate's standings model would be worse in raids: more bosses, more players, more
    per-player rows and a bigger full-table reload.

Conclusion: raids are a separate design after dungeons. They need lockouts, 10/25 difficulty,
multi-encounter completion, raid loot tables and a weekly reset. Do not bolt them onto v1.

### Audit verdict

Not a drop-in. The module supplies a usable run-state skeleton and a working gossip/affix frame,
but it has no scaled loot or economy, covers only two old dungeons, writes per death and per boss
per player, reloads the whole standings table every ten minutes, and cannot support raids. Treat it
as a fork base, not as a vendor. The MIT licence makes that safe.

## Vendor or fork

- **Vendor unchanged + companion loot module.** Fastest path to a timer, and upstream stays clean.
  But two modules own the same instance state; the companion must patch around per-kill writes, the
  full standings reload, broken random affixes and the wrong boss data; config and DB are duplicated.
- **Fork at `e2a487d` and refactor.** One owner of run state; hot paths fixed once; the useful
  timer/affix/NPC skeleton is kept. Cost: upstream divergence, maintenance and a larger review.
- **Rewrite from scratch.** Clean design and no legacy. Cost: rebuild the timer, gossip, affix
  interface and run state; slower to a first playable slice.

**Recommendation: fork.** Vendor at pinned commit `e2a487d` into `modules/mod-mythic-plus`, keep
`LICENSE`, and add `UPSTREAM.md` with the repo, commit, licence and local-divergence list. Refactor
in slices: keep the run state machine, gossip skeleton and affix interface; replace creature
scaling, loot, standings, random affixes, SQL packaging, commands and the reward path. This follows
the existing vendored-module pattern in `modules/` and avoids a git submodule.

The fork must not be vendored until the spec is accepted. When it is, the upstream author credit
applies to the mirrored commit (`--author` or `Co-authored-by` for silviu20092), per AGENTS.md.

## Implementation slices

1. **Data and generator only.** Add the ladder, pool (Ragefire Chasm only), boss table, creature
   scale table, scaled-item schema, the native-item budget table and the `item_ids.csv` manifest.
   Generate the mapping and the compact `INSERT ... SELECT` materialization for Ragefire Chasm,
   key 1, Subterranean Cape (14149), the matching `item_dbc` rows, the `Item.dbc` row set, and the
   `data/client-patches/item-data/` manifest. Hand the row set to the accepted ADR-027 pipeline
   (`items.json`, `source/*.csv`, `generate_items.py`, whole-file `Item.dbc`, `manifest.json`),
   which owns the source `Item.dbc` merge and packaging. Include **one custom item in a bag** as a
   required acceptance test, not only a TryOn sample. Use QA-block probe `1900001`; do not use
   `2050641`, which collides with the transmog preview copy. No module code, no loot hook. Unit tests for
   determinism, ID ranges, budget scaling, exclusions, set curation and DBC-row equality. This
   proves client data delivery and the stat budget before gameplay work.
2. **Run engine, one dungeon.** Fork the module; keep only the timer/state machine for Ragefire
   Chasm. `.mythic start 1`, first-damage timer, death penalty, final boss 11520, abort on reset or
   restart. No loot, no coins.
3. **Loot and coins.** `OnBeforeDropAddItem` replacement for boss loot, final-boss personal item,
   pending rewards, in-memory coin accrual and one currency write at run end.
4. **Economy.** Quartermaster vendor, weekly stock, upgrade, recycle, weekly vault, per-character
   progress and the player commands with RBAC.
5. **Pool expansion.** Five Classic dungeons, then all Classic, then TBC and WotLK. Add the full
   boss/loot coverage tests at each step.
6. **Leaderboard and raids.** Leaderboard after the economy is stable; raids only after a separate
   ADR.

The first slice I recommend is **slice 1**. It is small, has a clear test, and fails early if the
merged `Item.dbc` does not render one custom item in the bag or the stat budget is wrong.

## Contract (proposed)

### Purpose

Give level-80 players a reason to run the Classic, TBC and WotLK five-player dungeons again. The
feature adds a per-era key ladder, scaled creature difficulty, scaled item copies, a weekly vault, a
currency vendor and a recycling sink. It does not add new maps, models, icons or spells.

### Scope

Five-player dungeons from all three eras, normal difficulty (**recommended, pending owner**; a
heroic ladder is not in v1). Keys 1–20. Scaled item copies, boss
loot replacement, final-boss personal loot, Mythic Coins, vendor, upgrade, recycle, weekly vault,
per-character progression (**recommended, pending owner**; account-wide is the alternative) and an
optional leaderboard. Raids are out of scope (**recommended, pending owner**; a separate ADR decides
them).

### Boundary (owns / does not own / consumes)

- Owns: the run state machine, key ladder, creature scaling, item-copy generation contract, loot
  replacement, coin economy, vendor and vault behavior, per-character progress, the leaderboard,
  and the `Item.dbc` row set and manifest.
- Does not own: dungeon scripts, boss mechanics, loot tables, item models, the **source `Item.dbc`
  merge and MPQ packaging** (ADR-027's pipeline owns those), the GM API, the website, or AutoBalance.
  It consumes existing `instance_template`, `creature_loot_template`, `item_template`,
  `instance_encounters` and `creature_template` data.
- The candidate module is audited in RFC-004. v1 is a fork, not an unchanged vendor.

### Behavior

#### Player flow

1. A level-80 character enters a normal dungeon in the pool, alone or in a group of up to five
   (**recommended, pending owner**; a strict five-player requirement is the alternative).
2. The group leader (the player when solo) runs `.mythic start <key>` while inside the instance,
   out of combat, with every group member online, level 80 and inside the same instance. The key
   must be at most `highest_key + 1` for every member's era, and at most 20; any member below the
   run key refuses the start (no carries). Starting is refused if a player or player-controlled
   unit has already killed a hostile creature in the instance; a pre-cleared instance cannot be
   turned into a run.
3. The run enters `prestart`. The timer starts on the first damage dealt to a hostile creature in
   the instance, not on the command. A 15-minute prestart timeout aborts the run.
4. Bosses drop scaled copies through the normal loot window. The final boss additionally grants one
   personal scaled item to every eligible player when the timer was beaten.
5. On the final boss kill the run completes. A completion inside the time limit (elapsed plus the
   death penalty) raises each eligible member's `highest_key` to `max(highest_key, key)`, capped at
   20, so the next startable key becomes `highest_key + 1`. A failed timer gives no
   unlock and no final-boss personal item, but still counts as a completion for the weekly vault.
6. Coins are credited once at run end. The weekly vault and the vendor are available in the world;
   no addon is required.

**Eligibility.** A character is eligible only when it is in the run's `member_guids` at start, has
not left the instance during the run, and is present in the instance at the final boss kill. The
run refuses to start unless every member satisfies `highest_key + 1 >= key`; carries are not
allowed. Once the run is active, only `member_guids` may enter or remain in the instance; a
non-member is teleported to the entry point. Late joiners are not eligible. A member who leaves and
rejoins is not eligible. Eligibility gates the key unlock, coins, vault credit and the final-boss
personal item.

Command list and classification:

| Command | Who | RBAC / audit |
|---------|-----|--------------|
| `.mythic info` | Player | Permission `950160`; Player role; no audit row. |
| `.mythic start <key>` | Group leader or solo player | Permission `950161`; Player role; no audit row. |
| `.mythic abandon` | Group leader or solo player | Permission `950162`; Player role; no audit row. |
| `.mythic status` | Administrator | Permission `950163`; admin role; audited with the other GM commands. |
| `.mythic reload` | Administrator | Permission `950163`; admin role; audited with the other GM commands. |

`.mythic info` shows the current run, key, timer, deaths and the character's highest key per era.
`.mythic abandon` is leader-only and aborts the run without rewards. `.mythic status` prints active
runs, loaded counts, item-map size and the last error. `.mythic reload` reloads the hot-reloadable
tables.

#### Dungeon pool

The pool is a data table, not a hardcoded list. v1 includes the following map IDs:

| Era | Maps |
|-----|------|
| Classic | 33, 34, 36, 43, 47, 48, 70, 90, 109, 129, 189, 209, 230, 289, 329, 349, 389, 429 |
| TBC | 269, 540, 542, 543, 545, 546, 547, 552, 553, 554, 555, 556, 557, 558, 560, 585 |
| WotLK | 574, 575, 576, 578, 595, 599, 600, 601, 602, 604, 608, 619, 632, 650, 658, 668 |

Blackrock Spire (229) is excluded because it is a ten-player dungeon. Onyxia's Lair and all raid
maps are excluded. Each row carries a base timer and a final boss entry. The final boss is validated
at boot against `creature_template` and `instance_encounters`; a mismatch disables the row and logs
an error. The candidate module's Ragefire Chasm row is an example of why this validation is needed:
it names Bazzalan (11519) instead of Taragaman the Hungerer (11520).

#### Key ladder

The ladder is data-driven. Each row is `(era, key_level, item_level)`. v1 values:

| Key | Classic | TBC | WotLK |
|-----|---------|-----|-------|
| 1 | 115 | 120 | 187 |
| 2 | 123 | 129 | 191 |
| 3 | 131 | 138 | 194 |
| 4 | 139 | 147 | 198 |
| 5 | 147 | 156 | 201 |
| 6 | 155 | 164 | 205 |
| 7 | 163 | 173 | 208 |
| 8 | 171 | 182 | 212 |
| 9 | 179 | 191 | 215 |
| 10 | 187 | 200 | 219 |
| 11 | 192 | 203 | 220 |
| 12 | 196 | 206 | 221 |
| 13 | 201 | 210 | 223 |
| 14 | 205 | 213 | 224 |
| 15 | 210 | 216 | 226 |
| 16 | 214 | 219 | 227 |
| 17 | 219 | 223 | 229 |
| 18 | 223 | 226 | 230 |
| 19 | 228 | 229 | 231 |
| 20 | 232 | 232 | 232 |

The anchors are deliberate: Classic M10 equals item level 187, the normal WotLK dungeon level; TBC
M10 equals 200, the WotLK heroic dungeon level; WotLK M1 is 187 and M10 is 219, the heroic WotLK
five-player ceiling. Re-anchoring WotLK M1 at 187 avoids compressing 19 keys into 32 item levels;
the 200 `min_item_level` floor handles ToC, Forge of Souls, Pit of Saron and Halls of Reflection.
The top ten steps (219→232) are still 1–2 item levels; that compression is accepted, and a paid
upgrade whose target item level equals the current item level is refused rather than sold as a
power gain.

Dungeon ladders stop at 232, the Trial of the Crusader ten-player normal level, at M20. 232 does
not obsolete ToC 25 / ICC loot, but it exceeds Naxxramas 25 (213) and Ulduar normal (219/226) and
equals ToC 10 normal. Item level 284 remains the global system cap for future raid ladders, not a
v1 dungeon reward. The 232 dungeon cap is **recommended, pending owner**.

A dungeon may set `min_item_level` above the ladder value (for example ToC, Forge of Souls, Pit of
Saron and Halls of Reflection have a native 200 floor). The effective target is
`max(ladder_item_level, dungeon.min_item_level)`, so a higher difficulty never pays a lower item
level than the same dungeon already drops. Boot validation requires
`min_item_level <= ladder[era][20]`; a mis-set floor is a hard load error, not a silent clamp.

#### Item copies

Every obtainable source item is copied for every key level of its era. The copy is a real
`item_template` row; the module never changes item stats at runtime.

**Source set.** Start from `creature_loot_template` rows of the bosses in `mythic_plus_boss`,
including referenced `reference_loot_template` rows. Include only items with `class = 2` (weapon)
or `class = 4` (armor), `Quality` 2–4, `ItemLevel > 0`, and a real source in the pool. A source item
that appears in two eras gets two separate copy sets.

**Exclusions.** Legendary quality (5) and artifact quality (6); `RandomProperty` or `RandomSuffix`
non-zero; `duration` non-zero; `maxcount = 1`; shirt and tabard **inventory types** (4 and 19), not
armor subclass 0 — rings, necks, cloaks and trinkets are class 4, subclass 0 and must stay in the
pool; fishing poles, miscellaneous weapons, obsolete weapons and quest items; names matching the
generator's deny list (`Test`, `Deprecated`, `Monster -`, `NPC`, `Old`, `Broken`); and any entry in
the curation file. The curation file is `tools/dev/mythic-plus/curation.json` and is reviewed with
the generated SQL.

**Stats: budget parity, not power parity.** A raw `target / source` item-level ratio is not enough:
a Classic item scaled to 232 would keep a Classic stat curve and could be much weaker than a native
232 item while claiming the same item level. The generator uses a committed budget table,
`tools/dev/mythic-plus/item_budget.csv`, derived from native items in `item_template`:

- `stat_budget(item_level, quality, slot_group)` is the median total raw stat points of native
  items at that item level, quality and slot group (head/chest/legs, shoulders/hands/feet,
  wrist/waist, neck/ring/trinket/back, one-hand, two-hand, shield/off-hand). "Raw" means the sum of
  the absolute values of the ten `stat_value` columns **plus** the six resistance fields; no
  arbitrary stat weights are invented, and a negative stat cannot inflate the factor.
- `armor_budget` and `weapon_dps_budget` are the matching medians for armor and weapon DPS. Only
  native items with no random suffix or property are sampled, so the budget is not inflated by
  random rolls.
- Missing item levels are interpolated between the nearest samples; no extrapolation above 232 for
  dungeons. If a quality has no sample at all, use the nearest quality with samples and record the
  fallback in the generator report; never invent a budget.

Budget parity is not power parity. Items whose budget is dominated by dead stats (for example
spirit or MP5 on a class that cannot use it, or hit rating past the cap), by an unscaled proc or
on-use effect, or by a set bonus are excluded or flagged in the curation report. They are not
claimed to be equivalent to a native item at the same item level.

Let `S` be the source row and `T` the effective target. The generator computes
`factor = stat_budget(T, S.Quality, slot_group(S)) / max(raw_stat_total(S), 1)`, then writes:

- `ItemLevel = T`, `RequiredLevel = 80`.
- Every non-zero `stat_value` is multiplied by `factor` and rounded half away from zero. Negative
  values stay negative. The sum of the scaled stats approximately matches the target budget; the
  generator tolerates rounding to whole stat points. The generator clamps the target budget so
  positive stats are non-decreasing across keys; equal values at the cap are allowed.
- `armor` and `block` scale by
  `armor_budget(T, S.Quality, slot_group) / armor_budget(S.ItemLevel, S.Quality, slot_group)`;
  weapon `dmg_min1`/`dmg_max1`/`dmg_min2`/`dmg_max2` scale by
  `weapon_dps_budget(T, S.Quality, slot_group) / weapon_dps_budget(S.ItemLevel, S.Quality, slot_group)`.
  `dmg_type1`, `dmg_type2` and `delay` are unchanged.
- `holy_res`, `fire_res`, `nature_res`, `frost_res`, `shadow_res` and `arcane_res` scale with the
  stat factor, count in the raw budget, and are capped at 50 per school.
- `ScalingStatDistribution = 0` and `ScalingStatValue = 0` so the core cannot recompute the stats
  from player level.
- `RandomProperty = 0`, `RandomSuffix = 0`, `duration = 0`, `maxcount = 0`, `stackable = 1`,
  `startquest = 0`, `lockid = 0`, `PageText = 0`, `Map = 0`, `area = 0`, `HolidayId = 0`,
  `ItemLimitCategory = 0`, `FoodType = 0`, `minMoneyLoot = 0`, `maxMoneyLoot = 0`, `BuyPrice = 0`,
  `SellPrice = 0`, `DisenchantID = 0`, `VerifiedBuild = 0`.
- `Flags` keeps `ITEM_FLAG_UNIQUE_EQUIPPABLE` (`0x00080000`),
  `ITEM_FLAG_NOT_USEABLE_IN_ARENA` (`0x04000000`), `ITEM_FLAG_NO_DURABILITY_LOSS` (`0x00400000`)
  and `ITEM_FLAG_USE_WHEN_SHAPESHIFTED` (`0x00800000`) from the source; unrelated bits are cleared.
  `FlagsExtra` keeps only `ITEM_FLAG2_FACTION_HORDE` (`0x00000001`) and
  `ITEM_FLAG2_FACTION_ALLIANCE` (`0x00000002`); unrelated bits are cleared. Do not zero these
  columns wholesale: the allowlisted behavior and faction restrictions must survive.
- `bonding = 1` (bind on pickup). `name = original name + " (M+" + key + ")"` and `description`
  states the era and key. `Quality`, `class`, `subclass`, `SoundOverrideSubclass`, `displayid`,
  `InventoryType`, `sheath`, `Material`, `socketColor_*`, `socketBonus`, `GemProperties`,
  `MaxDurability`, `AllowableClass`, `AllowableRace`, `RequiredSkill`, `RequiredSkillRank`,
  `ArmorDamageModifier`, `RangedModRange`, `ammo_type`, `flagsCustom`, and `spellid_1..5` with
  their triggers and cooldowns are preserved. Class-restricted relics, librams, idols and totems
  stay class-restricted; ranged items keep their range modifier.
- A flat proc or on-use spell on the source item keeps its original effect. It does not scale.
  Items whose power is dominated by such an effect are excluded by curation rather than left to
  become an outlier.

**Sets and legendaries.** A copy keeps `itemset` only when the set is on the curated allowlist and
every piece of that set is in the same era pool. Otherwise the copy gets `itemset = 0`. Legendary
items are never copied. Raid tier sets are deferred with raids.

**IDs and manifest.** Obtainable copies use `1100000–1899999`. Non-obtainable and QA copies use
`1900000–1999999`; they are never placed in loot, a vendor or the vault. Preview items keep
`2000000–2999999`: a preview entry is `2000000 + source_entry`, so a source entry of `1000000` or
more would land at `3000000` or above. Reserve `3000000–3999999` for previews of seven-digit source
IDs, and make the transmog preview generator refuse any computed id outside the two preview blocks
(the generator's source set is below `1000000` today, which is why `2000000–2999999` still holds).
The block starts at 1,100,000 because creature `1000003` and npc_text `1000004`
are already registered below it; do not reuse the numeric space below the highest registered
custom ID. A committed manifest (`tools/dev/mythic-plus/item_ids.csv`) records every
`(source_entry, era, key_level) -> scaled_entry` assignment. Every key gets its own generated item
ID, even when the target item level is capped; this keeps upgrade pricing and item identity
unambiguous. Regeneration keeps existing assignments and never reuses a retired ID. The generator
fails when one ID is assigned to two different `(source_item, era, key_level)` identities, when an
ID is outside the ranges, or when a source item is itself in the generated range.

**Immutable rows and soft retirement.** Once a generated item is obtainable, its `item_template`
row is immutable. Do not `DELETE` it and do not rewrite its stats: a player may still own it. A
retired item is removed from new drops, vendor stock and the vault by setting
`mythic_plus_scaled_item.active = 0`; the item remains resolvable for upgrade and recycle. A stat
formula change needs new IDs and a new generation decision, not an update to an existing row. The
same rule applies to the server `item_dbc` row.

**Storage and generation.** A 100,000-row, 200-column `item_template` dump would be hundreds of
megabytes and is not committed. The generator emits a compact mapping file and a compact
materialization file:

- `mythic_plus_scaled_item.sql`: the pool, ladder, budget, boss and mapping rows. The mapping is
  seven columns (`source_entry`, `era`, `key_level`, `scaled_entry`, `target_ilvl`, `obtainable`,
  `active`) and about 60,000 rows; the same file carries the pool, ladder, budget and boss rows.
- `mythic_plus_item_rows.sql`: `INSERT IGNORE ... SELECT` from `item_template`,
  `mythic_plus_scaled_item` and the budget table, with the scaling expressions in SQL. MySQL
  materializes missing rows at apply time; existing generated rows are never updated or deleted.
  No item is mutated at runtime.
- `mythic_plus_item_dbc.sql`: the matching server `item_dbc` rows, built from the same join, also
  `INSERT IGNORE`.
- `data/client-patches/item-data/`: the client handoff in the accepted ADR-027 shape — `items.json`,
  `source/*.csv`, `generate_items.py`, the whole-file `Item.dbc` and `manifest.json`. ADR-027's
  pipeline owns the source `Item.dbc` merge and MPQ packaging; no row fragment ships on its own.
  The first slice must include one custom item in a bag, not only a TryOn sample.
- `item_ids.csv` and `item_budget.csv`: the committed generator inputs and audit trail.

The generator is deterministic and idempotent. A build check recomputes every row's expected
stats/checksum from the source row, budget and ladder, compares it with the materialized
`item_template` row, and also compares row counts. Any per-row drift or count mismatch fails the
build. The generator inserts only **missing** `mythic_plus_scaled_item` rows: it never `DELETE`s or
`UPDATE`s an existing mapping, so a retired row (`active = 0`) stays retired across regeneration;
only a new `(source_entry, era, key_level)` identity adds a row. This generated SQL intentionally
does **not** use
the house `DELETE`-before-`INSERT` rule: deleting a generated ID could remove an item a player still
owns. The exception is an open owner decision in
[OPEN-QUESTIONS.md](../../decisions/OPEN-QUESTIONS.md) ("Generated SQL without
`DELETE`-before-`INSERT`"); acceptance must update `.agents/docs/sql-guidelines.md` and the
`make verify-sql` change to document and allow immutable generated files. **No such exception is
documented yet.**

**Server and client data — confirmed.** Every generated item gets an `item_template` row, a matching
server `item_dbc` row in `data/sql/custom/db_world/`, and a client `Item.dbc` row. The `item_dbc`
fields (class, subclass, material, display, inventory type, sheath) are copied from the source
item's `item_dbc` row, or derived from `item_template` when the source has no row.

The client boundary was tested on 2026-11-23: a server-only `item_template` row with no `Item.dbc`
entry shows a **red question mark in the bag**. Use QA-block item `1900001` for the formal probe;
the earlier `2050641` collides with the transmog preview copy at `50641 + 2000000`, so it is not a
safe probe. The transmog preview model still worked because `TryOn` uses the server display ID; that
path is separate and is not evidence that the bag entry works. New scaled item IDs therefore
**require** a client `Item.dbc` row. A data-only client patch is allowed; ADR-027's pipeline owns the
source-DBC merge and MPQ packaging; no executable client change is needed.

Preview items at `2000000–2999999` are real on `local-server-setup` (ADR-026 revision,
`transmog_preview_items.sql`); this branch base predates that merge. They remain a separate
server-display path and do not remove the `Item.dbc` requirement for bag entries.

#### Loot

- **Boss loot.** `GlobalScript::OnBeforeDropAddItem` receives a mutable `LootStoreItem`. The
  replacement is gated on an **active run row** for the instance and its stored key, not merely on
  a Mythic+ capable map. With no active run, loot is unchanged. For a boss loot row on an active
  run, the module replaces `itemid` with the generated entry for `(source_entry, era, key)`. One
  hash lookup, no database query. The hook only sees concrete, non-reference rows: the core expands
  `reference_loot_template` rows before calling it, so a reference row never reaches
  `OnBeforeDropAddItem` (the items it expands to do, as plain rows). Quest-required rows, gold,
  trash loot and non-boss loot are left alone. Creature loot only: reward chests that use gameobject
  loot — the Trial of the Crusader chest and the Dire Maul tribute chests — are **not** replaced in
  v1 and still drop their original items. A mapping outside the obtainable range or with
  `active = 0` is refused and
  logged. A missing mapping logs a warning and keeps the original item; it never crashes and never
  writes per kill.
- **Final boss.** Each eligible player receives one personal copy from the final boss's active
  scaled armor/weapon pool, or from the dungeon pool when the final boss has none. It is a direct
  inventory grant; if the bags are full it goes to `mythic_plus_pending_reward`, never to mail. It
  is granted only when the timer was beaten and an active run exists.
- **Weekly vault.** Once per character per UTC week, if the character was eligible for at least one
  completed run that week, the vault offers three deterministic choices from the era of the
  **best effective reward** completed that week, ranked by the effective item level of the key
  (`max(ladder_item_level(era, key), that dungeon's min_item_level)`), then by key, then by earliest
  completion. Do not rank by raw key number: Classic 10 (187) is below WotLK 9 (215). The choices
  are seeded by
  `(week_id, era, character GUID)`, so reopening the vault shows the same three items. The player
  picks one. No reroll. Bags full uses the pending-reward table.
- **Vendor.** A Mythic Quartermaster sells six deterministic **active** items per era per week
  (**recommended, pending owner**; a random cache is the alternative), chosen from the era pool with
  a `(week_id, era)` seed. The stock is at the character's highest key
  (minimum 1). An item
  at key `K` costs `30 + 15 * K` coins (45 at key 1, 180 at key 10, 330 at key 20). The vendor does
  not buy items for gold. The same NPC opens the weekly vault and the pending-reward claim. Its
  creature entry is `910013` (Mythic Quartermaster); the spawn is placed at implementation and the
  template is recorded in the ID registry. Its model is an existing creature display.
- **Upgrade.** An owned obtainable scaled item (`1100000 <= scaled_entry < 1900000`, `active = 1`
  or retired) can be upgraded to any key up to the character's highest key. Resolve the item's
  current key from its `scaled_entry`, then price the difference. Refuse when the target key is not
  higher, or when the target item level equals the current item level. The per-dungeon floor is the
  real source of equal steps: ToC, FoS, PoS and HoR resolve keys 1–4 to their 200 floor (the WotLK
  ladder is 187, 191, 194 and 198 there; key 5 is 201). The 232 ceiling is not a collision — every
  era's M20 is above its M19 (Classic 228→232, TBC 229→232, WotLK 231→232). The old item is
  destroyed before the new one is granted. The
  replacement keeps the same `source_entry`, era and item identity. Equipped items are refused.
- **Recycle.** An owned obtainable scaled item can be recycled for
  `floor(price(resolved_current_key) * 0.4)` coins. A confirmation gossip option is required. The
  item is destroyed before the coins are credited. A retired item still resolves for recycle.
- **Coins.** Five coins per non-final boss killed, fifteen for the final boss instead of five, and
  ten for a timed completion: `5 × (bosses − 1) + 15 + (10 if timed)`. A four-boss run inside the
  timer pays 3 × 5 + 15 + 10 = 40. Coins are awarded once at run end, not per kill, to eligible
  members only. No cap, no real-money purchase, no gold conversion, no trade, no auction house, no
  mail. GM-mode characters are not eligible.

#### Progression, currencies and storage

- `mythic_plus_progress(guid, era, highest_key)`: per character, per era (**recommended, pending
  owner**; account-wide is the alternative). `highest_key` is the highest key **completed**; a run
  may start at `highest_key + 1` or below. A timed completion by an
  eligible member raises it to `max(highest_key, key)`, capped at 20, so the next startable key is
  `highest_key + 1` and a completion can never skip a key. A failed timer or an
  ineligible member does not change it.
- `mythic_plus_currency(guid, coins)`: per character balance. It is a table, not an item, so it has
  no stack cap and cannot be traded.
- `mythic_plus_weekly_reward(guid, week_id, era, highest_key, claimed_entry)`: one row per **eligible**
  character per week, written at run completion for the run with the best effective reward that week
  (`highest_key` stores that run's key, `era` its era; a tie keeps the earlier run), and filled in
  when the vault item is claimed. Ineligible members get no row. `week_id` is
  `floor((unix_time - anchor) / 604800)` with the anchor fixed at a Tuesday 00:00 UTC; the reset is
  Tuesday 00:00 UTC (**recommended, pending owner**). It is not an ISO week number, because ISO
  weeks start on Monday.
- `mythic_plus_pending_reward`: items that did not fit in bags. Claimed at the quartermaster.
- `mythic_plus_run`: one row per instance run, written at start and at completion/abort. It stores
  the map, era, key, leader, state, deaths, affix mask, member GUIDs, start time, end time and
  duration. At world start, **every** row with `state = active` is marked `abandoned`; a restart
  aborts every run and no timer survives. Before that sweep, an active row older than 24 hours logs
  an ERROR for crash detection only; age is not the abandonment condition. Completed or abandoned
  rows are pruned after 30 days by one indexed statement at world start, never on a timer.
- `mythic_plus_leaderboard`: one row per completed run, inserted at completion, indexed by
  `(map_id, key_level, duration_ms)`. It stores `leader_guid` and a comma-separated `member_guids`
  list, not names. Display resolves names with **one batch query** per gossip page:
  `SELECT guid, name FROM characters WHERE guid IN (...)` for the page's rows only; no N+1 lookup.
  Insert carries a top-100-per-`(map_id,key_level)` prune (one indexed `DELETE`); expired rows are
  pruned at world start and retained for 90 days. Leaderboard rows are optional for v1
  (**recommended, pending owner**: after the economy, before the website) but the
  table, name-resolution rule and retention are part of the contract.

#### Instances and lockouts

- Only normal difficulty (spawn mode 0) is Mythic+ capable (**recommended, pending owner**; a
  heroic ladder is not in v1). A heroic instance is refused.
- One active run per instance. A completed or abandoned instance cannot start another run; reset the
  instance to get a new instance ID.
- While a run is active, only its `member_guids` may enter or remain in the instance. A non-member,
  late joiner or member who left and rejoined is teleported to the entry point and gets no reward.
- The core five-instances-per-hour account limit stays in force. Mythic+ runs count against it.
- No raid lockouts, no lockout extension, no lockout sharing.
- Instance reset or map destruction aborts the run: no unlock, no vault credit, no coins. A server
  restart aborts every active run for the same reason.
- The group may skip optional bosses. Only the final boss completes the run; skipped bosses pay no
  coins.

#### Affixes and timer

- The timer is `base_time_seconds` from the dungeon row. Key level does not change it. A death after
  the timer starts adds five seconds. The timer starts on the first damage from a player or
  player-controlled unit to a hostile creature in the instance; a scripted mob fight does not start
  it. It stops at the final boss kill.
- Affixes are data rows `(era, min_key, affix_type, value1, value2)`. v1 ships deterministic
  affixes, not random ones. Each is active from its `min_key` through key 20:

  | Affix | From key | Effect | Reused spell (placeholder) |
  |-------|----------|--------|------------------------------|
  | Raging | 4 | A hostile creature below 30% health gains +50% damage. | 55285 (Enrage) |
  | Explosive | 7 | Every 10 seconds one random player explodes for 15% of maximum health. | 71495 (visual) |
  | Entangling | 10 | Every 20 seconds one random player is rooted for 6 seconds. | 57095 (Entangling Roots) |

  Spell IDs 55285, 71495 and 57095 are **placeholders** taken from the candidate module. Slice 1
  verifies each against the client `Spell.dbc` and in-game behavior, and replaces any wrong ID with
  an existing spell. Higher keys rely on creature scaling plus these affixes. Values are playtest
  knobs in SQL. No new spell IDs are introduced, so there is no client spell patch.
- The run stores an affix mask so a later audit can reproduce the run. Random affixes are not
  allowed in v1. If they return, the seed is stored on the run and the selection is per run, never
  per server restart.
- Affix periodic effects run from the map update for active Mythic+ maps only. No per-unit update
  hook is allowed.

#### Creature scaling

- Scale once when the run starts by iterating the instance's loaded creature store, and on
  `OnCreatureAddWorld` for creatures spawned afterwards. A per-creature flag keyed to the run ID
  prevents a remove/re-add from scaling twice. No `OnAllCreatureUpdate` and no per-tick scan.
- Scale only hostile creatures: skip critters, totems, triggers, player-controlled pets/summons,
  friendly NPCs, civilians and non-attackable units. This protects escorts, vendors and quest NPCs.
- Set level 80–82, then apply health and damage multipliers from `mythic_plus_creature_scale`,
  keyed by `(era, key_level, is_boss)`. The values are playtest knobs in SQL, not constants in C++.
  The existing server creature HP rate still applies; do not multiply it twice.
- Boss detection is `(map_id, entry)` from `mythic_plus_boss` plus `IsDungeonBoss()`. Never use a
  global final-boss entry; entries are reused across maps.
- Starter values, to be replaced by measured playtest values: boss health
  `1 + 0.12 * (key - 1)`, trash health `1 + 0.08 * (key - 1)`, damage `1 + 0.06 * (key - 1)`.
  They are data rows, not constants.
- AutoBalance and Mythic+ must not both scale the same map. Refusing to start while AutoBalance is
  on is **recommended, pending owner**; disabling AutoBalance on Mythic+ capable maps is the
  alternative. If the AutoBalance module is installed,
  read its module config key `AutoBalance.Enable.Global` (module-defined, not a core key in this
  repo) and refuse to start runs when it is on. If the module is absent, skip the check and log
  nothing. The owner may instead disable AutoBalance on Mythic+ maps; one module owns the scale.

#### Data model

World database, custom SQL, re-applicable:

```text
mythic_plus_dungeon_pool(map_id PK, era, base_time_seconds, final_boss_entry,
    min_item_level, enabled, KEY(era))
mythic_plus_key_ladder(era, key_level, item_level, PK(era,key_level))
mythic_plus_item_budget(item_level, quality, slot_group, stat_budget, armor_budget,
    weapon_dps_budget, PK(item_level,quality,slot_group))
mythic_plus_scaled_item(source_entry, era, key_level, scaled_entry, target_ilvl, obtainable,
    active, PK(source_entry,era,key_level), UNIQUE(scaled_entry), KEY(era,key_level))
mythic_plus_creature_scale(era, key_level, is_boss, health_multiplier, damage_multiplier,
    PK(era,key_level,is_boss))
mythic_plus_boss(map_id, entry, is_final, PK(map_id,entry))
mythic_plus_affix(era, min_key, affix_type, value1, value2, PK(era,min_key,affix_type))
mythic_plus_itemset_allowlist(itemset_id, era, note, PK(itemset_id,era))
```

Characters database:

```text
mythic_plus_progress(guid, era, highest_key, updated_at, PK(guid,era))
mythic_plus_currency(guid PK, coins, updated_at)
mythic_plus_run(instance_id PK, map_id, era, key_level, leader_guid, state, deaths, affix_mask,
    started_at, completed_at, duration_ms, member_guids, KEY(state), KEY(started_at),
    KEY(completed_at))
mythic_plus_weekly_reward(guid, week_id, era, highest_key, claimed_entry, claimed_at,
    PK(guid,week_id), KEY(week_id))
mythic_plus_pending_reward(id PK AUTO_INCREMENT, guid, item_entry, count, reason, created_at,
    KEY(guid))
mythic_plus_leaderboard(run_id PK, map_id, key_level, duration_ms, completed_at, leader_guid,
    member_guids, KEY(map_id,key_level,duration_ms), KEY(completed_at))
```

`mythic_plus_scaled_item` is the only large table (roughly 60,000–100,000 rows). It is loaded once
into an `unordered_map` keyed by `(source_entry, era, key_level)` with `reserve()`. At 100,000
entries the mapping itself is a few megabytes, not tens; the exact figure is measured in slice 1.
The loot path does one lookup. No runtime SQL in the loot path and no `item_template` scan.

#### Performance for 5,000–7,000 players

- Boot: one SELECT per table, batch-loaded; target low single-digit seconds for the item map. No
  accepted memory number yet. Slice 1 measures three components separately: (a) the module's
  `unordered_map`, (b) 100,000 `ItemTemplate` cache entries, and (c) `item_dbc`/`sItemStore`
  entries. The current world is 46,096 `item_template` rows (world export, 2026-11-18); the
  generated set adds roughly 60,000–100,000 rows. Do not claim a single `<100 MB` figure for one
  component.
- No per-tick global scan. Map update work exists only for active Mythic+ maps and is bounded per
  map (timer plus active affix effects). There is no `OnUnitUpdate` or `OnAllCreatureUpdate` hook.
- No per-kill writes. Boss and coin state is in memory; one currency write per player at run end.
  Deaths are in memory; the run row is written at start and at completion/abort.
- Loot replacement is O(1) per loot item and only when an active run row exists for the instance.
- Leaderboard inserts are one row per completed run; queries use the composite index. There is no
  periodic full-table reload like the candidate module's ten-minute standings refresh.
- Weekly and vendor stock are computed on demand from a week seed; no cron. A per-player weekly row
  is written at run completion, and a currency or vault row is written at run end or claim.
- All character-table hot queries are primary-key lookups. `EXPLAIN` every new query in the test
  plan; no full scans on `mythic_plus_*`.

### Security

- Server-side validation only. The client cannot start a run, choose an item, grant coins, or
  bypass a key check. There is no addon protocol.
- The leader check, group membership, level 80, same instance, normal difficulty, key ceiling,
  combat state and active-run check all run on the server.
- Commands are RBAC-gated. `950160` (`info`), `950161` (`start`) and `950162` (`abandon`) are
  player permissions granted to the Player role; `950163` guards `status` and `reload` for the admin
  role and is audited. The core command security alone is not the gate; ADR-009 applies.
- SQL uses prepared statements and typed parameters. Character names, if stored at all, are
  parameterized; no string concatenation. Logs carry GUIDs and instance IDs, not character names.
- Coins are server-side rows. Items are bind-on-pickup, not tradeable, not auctionable and not
  mailable. No gold price is accepted. The shop is unchanged and sells no power.
- Vendor and recycle operations remove the item before crediting value, run in one player item
  transaction where the core allows it, and are covered by duplication tests.
- GM-mode characters cannot start a run and get no loot, coins, vault credit or progress. GM grants
  stay on the audited GM command/API path, never raw SQL.
- Rate-limit `.mythic start` and vendor purchase confirmations per player to stop packet/command
  spam. No client-supplied item or key value is trusted.

### Observability

- INFO: module load counts (pool rows, ladder rows, item mappings, boss rows), run start, run end,
  run abort, result, key, era, duration, coin total.
- WARN: missing item mapping, full bags (pending reward), invalid key, invalid boss row, AutoBalance
  conflict, stale active run marked abandoned at boot.
- ERROR: database failure, generated-ID collision, out-of-range ID, item map load failure. The
  module refuses to start runs when its item map is incomplete; it does not run with partial data.
- No per-kill or per-death log lines. No player names in logs.
- `.mythic status` (admin) prints active runs, loaded counts, item-map size, and the last error.

### Errors and edge cases

- Missing mapping: keep the original item and log a warning; the run continues.
- Generated item missing from `item_template`: boot validation fails and the module disables runs.
- Ladder row missing: clamp to the nearest lower key and log; never index out of range.
- Final boss row invalid: disable that dungeon only; log the map and entry.
- `min_item_level > ladder[era][20]`: hard boot error; the module refuses to start runs rather than
  silently clamping a mis-set floor.
- Bags full: pending reward, claim at the quartermaster; never mail.
- Player leaves and rejoins, joins late, or is not in the instance at the final boss: not eligible,
  no unlock, coins, vault credit or final-boss personal item. The run refuses to start when any
  member's `highest_key + 1` is below the key (no carries).
- Group larger than five or a raid group: refuse to start.
- Instance reset or server restart: active run becomes abandoned; no rewards, no unlock.
- Timer expiry: no final-boss personal item and no unlock; boss loot already picked up stays; coins
  are still credited at run end; vault credit is still earned for the completion.
- Duplicate `.mythic start`: refuse while a run is active.
- A player at key 20: no further unlock; the run still pays coins and vault credit.
- A generated copy on a floor collision (ToC, FoS, PoS and HoR resolve keys 1–4 to their 200 floor):
  every key keeps its own item ID even when the target item level is unchanged; the upgrade service
  refuses an upgrade whose target item level does not change. The 232 ceiling is not a collision:
  every era's M20 is above its M19 (Classic 228→232, TBC 229→232, WotLK 231→232).
- A retired generated item: it stays in `item_template`, is excluded from new drops, vendor and
  vault, and still resolves for upgrade and recycle. No ID is reused.

### Test plan

#### Tier 0 — static and unit

- Generator is deterministic: two runs produce identical SQL and manifest.
- Every generated ID is inside `1100000–1899999` (obtainable) or `1900000–1999999` (QA); no collision
  with the source item range or registered custom IDs `1000003`/`1000004`.
- A preview id computed as `2000000 + source_entry` lands in `2000000–2999999` for a six-digit source
  and `3000000–3999999` for a seven-digit source; the transmog preview generator refuses any id
  outside those two blocks.
- Every generated row has `RequiredLevel = 80`, `ItemLevel` equal to the effective target
  (`max(ladder, dungeon.min_item_level)`), no random suffix/property,
  `ScalingStatDistribution = 0`, `bonding = 1`, and no legendary quality.
- Positive stat values are **non-decreasing** across keys for the same source item; equal values at
  the 232 cap are allowed. Negative stats stay negative and do not flip sign; the generator
  enforces the non-decreasing target budget rather than relying on rounding.
- `Flags` keeps unique-equippable, no-arena, no-durability-loss and use-in-shapeshift; every other
  `Flags` bit is cleared. `FlagsExtra` keeps the Horde/Alliance bits. Preserved columns
  include `AllowableClass`, `AllowableRace`, `RequiredSkill`, `RequiredSkillRank`,
  `ArmorDamageModifier`, `RangedModRange`, `ammo_type` and `flagsCustom`.
- Rings, necks, cloaks and trinkets (class 4, subclass 0) are present; shirt/tabard inventory types
  4/19 are absent.
- Resistances count in the budget and are capped at 50 per school.
- Applying the generated SQL twice inserts no duplicate rows and deletes no generated item; a
  retired mapping still resolves for upgrade/recycle.
- Per-row build check: recomputed stats/checksum equals the materialized row; deliberate drift
  (one stat point, one row, one ID) fails the build, not only a count mismatch.
- A set ID is kept only for a complete, allowlisted set; legendaries are absent.
- Ladder has 3 × 20 rows; every pool map has an era, timer, final boss, `min_item_level` and at
  least one boss loot source. WotLK M1 is 187; ToC/FoS/PoS/HoR resolve to 200 through the floor.
- A `min_item_level` above `ladder[era][20]` (232) fails boot validation.
- Every member's `highest_key + 1` is checked against the run key at start; a lower member refuses
  the run (no carries).
- Progression never skips: completing key K sets `highest_key = max(highest_key, K)`; a run at
  `highest_key + 1` is allowed and `highest_key + 2` is refused, including after repeating a lower
  key.
- SQL lint passes for hand-written SQL. The generated immutable files currently fail the
  `DELETE`-before-`INSERT` rule; the open question in
  [OPEN-QUESTIONS.md](../../decisions/OPEN-QUESTIONS.md) and the change to
  `.agents/docs/sql-guidelines.md` / `make verify-sql` must be resolved before acceptance. Docs
  links pass and the generated SQL is re-applicable.

#### Tier 1 — one dungeon, one key, one item

Use Ragefire Chasm (389), key 1, Subterranean Cape (14149) from Taragaman the Hungerer (11520).
Classic M1 target is item level 115. 14149 carries 8 stat points and 17 armor with no spell, so it
proves stat and armor scaling; Cursed Felblade (14145, the same boss) has 0 stats, 0 armor and an
on-hit proc, so it cannot prove the stat budget. Verify:

- The generated item has the expected scaled armor/damage/stats, a level-80 requirement, the original
  display and a key suffix.
- The boss loot window contains the generated item instead of 14149; the original item never drops.
  The hook sees only concrete rows: the reference rows in `creature_loot_template` are expanded by
  the core before `OnBeforeDropAddItem`, so a reference entry never reaches the replacement.
- The final boss grants the personal item once per eligible player; the timer, death penalty and
  final-boss entry are correct.
- Coins, vendor stock, upgrade and recycle work once; no duplication after a relog.
- Coin arithmetic: a four-boss run inside the timer pays 3 × 5 + 15 + 10 = 40; the same run after
  the timer pays 35.
- **One custom item in a bag (required, not optional):** generate the `Item.dbc` row set and
  manifest, hand them to the ADR-027 pipeline for the source-DBC merge and MPQ packaging, then
  `.additem` and loot the item. Use QA-block item `1900001` as the probe; `2050641` collides with the
  transmog preview copy. Verify bag icon, tooltip, equip and character model. The baseline is
  confirmed: a server-only probe with no `Item.dbc` row shows a red question mark. After the patch
  it must render normally. The transmog TryOn preview is a separate path and does not satisfy this
  test.

#### Tier 2 — five-dungeon pool

Ragefire Chasm, The Deadmines, Shadowfang Keep, Wailing Caverns and Blackfathom Deeps. Verify every
final boss row, every boss loot mapping, timer start on first damage, skip behavior, instance reset,
server restart (active runs abandoned), and a full clear at keys 1, 5 and 10. Verify the weekly vault
ranks by effective item level across eras: a Classic 10 completion (187) does not outrank a WotLK 9
completion (215), and a dungeon floor counts (ToC keys 1–4 resolve to 200).

#### Tier 3 — full era pools

All 18 Classic, 16 TBC and 16 WotLK maps. Verify pool coverage, no missing mapping for a boss drop,
boot time, and that no generated item is above 232. Confirm every mapping points at an existing
`item_template` row; the content audit still passes because the original loot tables are unchanged
and generated items are valid entries. Measure the three memory components and record the figures
in RFC-004 before accepting a budget.

#### Tier 4 — performance and security

- 100 concurrent runs (500 players) on a local stack; assert no `OnAllCreatureUpdate`/`OnUnitUpdate`
  hook in the module, no per-kill DB writes, and one currency write per player per run.
- `EXPLAIN` every new query; no full scans. Check the leaderboard query uses the composite index.
- Restart with active runs: every active row becomes `abandoned`, no timer or rewards survive; an
  active row older than 24 hours only produces a crash-detection ERROR before the sweep.
- Verify `mythic_plus_run` prune at 30 days, leaderboard prune at 90 days and top-100-per-pair
  pruning; verify leaderboard name resolution is one batch `IN` query per page, not one per row.
- Seven thousand account rows in `mythic_plus_progress`/`mythic_plus_currency`; login and vendor
  interactions stay under the latency budget.
- Attempt: start without leadership, start in combat, start at a key above the leader's ceiling,
  start with any member below the key ceiling (carry), start in a heroic instance, start with a
  level-79 member, start twice, start in a raid group, start while AutoBalance is on.
- Attempt: add a late joiner, leave and rejoin, be absent at the final boss, loot after the timer,
  re-loot a completed instance, reset during a run, relog during a run, full bags, vendor purchase
  with insufficient coins, recycle then restore, duplicate item via upgrade, mailbox/AH/trade of a
  generated item, GM-mode reward. Late joiners and leave/rejoin must get no unlock, coins, vault
  credit or final-boss item.
- Confirm command RBAC and audit rows for `.mythic reload`/`.mythic status`; confirm player commands
  are granted only to the Player role.

#### Tier 5 — balance and exploitation

- Compare M1, M10 and M20 clear times and damage taken with a normal WotLK dungeon at the same item
  level. Target 15–30 minutes for a competent five-player group at M1; tune the SQL multipliers.
- Confirm M10 Classic gear (187) is comparable to normal WotLK dungeon gear and does not exceed it
  beyond the intended stat budget.
- Confirm no item above 232, no set bonus from an incomplete set, no legendary, no random suffix.
- Confirm coins cannot be converted to gold, items cannot be traded, and no real-money path exists.
- Run the content audit and the existing unit tests; no regression in normal dungeons.

## Open questions for the owner

Client data is **resolved**: a data-only `Item.dbc` patch is required and allowed; the accepted
ADR-027 item-data pipeline is the delivery path. It is not an open question.

Every item below is a **recommendation pending owner**: the contract marks the same values
*recommended, pending owner*, and the entries live in
[decisions/OPEN-QUESTIONS.md](../../decisions/OPEN-QUESTIONS.md).

1. **Dungeon ceiling.** A five-player ladder at 232 (ToC 10 normal) at M20 does not obsolete ToC 25
   / ICC loot, but it exceeds Naxxramas 25 (213) and Ulduar normal (219/226). 284 is reserved for
   future raid ladders. Accept 232, or choose 245/284? The contract proposes 232, marked
   **recommended, pending owner**.
2. **Progression scope.** Per character or account-wide for progress, coins and vault?
   Recommendation: per character; account-wide only for cosmetics or teleports later.
3. **Raids.** In scope later? 10/25 or one size? Recommendation: separate ADR after dungeons.
4. **Group size.** Must a group be five, or is 1–5 allowed? Recommendation: allow 1–5 for
   accessibility, with no group-size scaling; owner may require five for key unlocks.
5. **Difficulty.** Normal only, or a second heroic ladder? Recommendation: normal only in v1.
6. **Weekly reset.** Tuesday 00:00 UTC? Recommendation: yes, a Tuesday-anchored week key, not an
   ISO week number.
7. **Vendor stock.** Deterministic six items per era per week, or a random cache? Recommendation:
   deterministic six; it is easier to audit and explain.
8. **Leaderboard.** v1 or after the website? Recommendation: after the economy, before the website.
9. **AutoBalance.** Disable it on Mythic+ maps, or make Mythic+ refuse to start while it is on?
   Recommendation: Mythic+ refuses; one module owns the scale.
10. **Generated SQL exception.** May immutable generated `item_template`/`item_dbc` files skip the
    house `DELETE`-before-`INSERT` rule? Recommendation: yes, documented in
    `.agents/docs/sql-guidelines.md` and allowed by `make verify-sql`, limited to generated rows.
    The exception is not documented yet; the entry is in `decisions/OPEN-QUESTIONS.md`.

## Impact

- World DB: about 60,000–100,000 generated item rows plus a compact mapping table. The item rows
  are materialized by a compact `INSERT ... SELECT`, not a giant dump. Measured baseline: 46,096
  `item_template` rows (world export, 2026-11-18). The mapping is a few megabytes by row count;
  exact memory is measured in slice 1, not claimed here.
- Client: a data-only `Item.dbc` patch is required for scaled item IDs; a server-only probe shows a
  red question mark without it. QA-block `1900001` is the formal probe; `2050641` collides with the
  transmog preview copy. ADR-027's pipeline owns the source-DBC merge and MPQ packaging. The
  preview/TryOn path is separate. No new maps, models, icons or spells.
- Characters DB: six small tables, primary-key lookups, one run row per run and one currency row per
  player per run.
- Operations: a new module, a new SQL set, a content-audit check for generated items and boss data,
  and a slice-1 `Item.dbc` merge with one custom item in a bag.
- **Acceptance:** update `AGENTS.md` custom-content reserved item ranges (currently
  `900000–909999`) to include `1100000–1899999`, `1900000–1999999`, `2000000–2999999` and
  `3000000–3999999` (or point at the registry), and resolve the TODO in `.agents/docs/sql-guidelines.md` / `make verify-sql` for immutable generated
  rows. That exception is not documented yet.
- No P2W: coins are earned, items are BOP, and nothing is sold for money.

## Decision record

Pending owner review of ADR-034. On acceptance, promote §Contract (proposed) into
`specs/mythic-plus.md`, update the ADR status and references, and move this RFC to `archived/`.

