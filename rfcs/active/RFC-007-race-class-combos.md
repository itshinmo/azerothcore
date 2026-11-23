# RFC-007 — Extended race/class combinations

- Status: discussion
- Date: 2026-11-23
- Author: research agent
- Related: [ADR-035](../../decisions/ADR-035-race-class-combos.md)
- Numbering: RFC-004 and RFC-006 are allocated on parallel branches and will be merged; RFC-005 is
  unassigned. If 007 collides at merge, renumber this RFC and its links.

This is a proposal. The target list and first batch are **not** owner decisions; they are tracked in
[decisions/OPEN-QUESTIONS.md](../../decisions/OPEN-QUESTIONS.md). The RFC keeps the durable contract
until [ADR-035](../../decisions/ADR-035-race-class-combos.md) is accepted. It does not touch the live
database or the client.

## Problem

Our 3.3.5 client and server allow only the stock WotLK race/class pairs. Project Ascension's
Bronzebeard realm unlocks additional pairs, and the owner asked for research on matching them.

The feature spans two independent gates:

- the **client** enumerates class buttons from `CharBaseInfo.dbc` and disables a class when
  `IsRaceClassValid(race, class)` is false;
- the **server** creates a character only when `ObjectMgr::GetPlayerInfo(race, class)` returns a
  `PlayerInfo` loaded from `playercreateinfo`.

A pair needs both. It also needs a starting position, starting outfit, action bar, weapon skills, a
reachable class trainer, the class quest chain, and the class's models/animations. Ascension's
character-customization pack (`patch-A.MPQ`) does not provide class-combo assets.

## Proposal

Target list (proposed, not approved) and recommended first batch (also not approved):

| # | Race | Class | RaceID | ClassID | Recommendation |
|---|------|-------|--------|---------|----------------|
| 1 | Dwarf | Mage | 3 | 8 | batch 1 |
| 2 | Orc | Mage | 2 | 8 | batch 1 |
| 3 | Gnome | Priest | 7 | 5 | batch 1 |
| 4 | Troll | Warlock | 8 | 9 | batch 1 |
| 5 | Blood Elf | Warrior | 10 | 1 | batch 1 |

Full proposed target from the Ascension wiki page (all rows are from that page):

| Race | Class | Client assets | Trainer / quests | Risk | Recommendation |
|------|-------|---------------|------------------|------|----------------|
| Undead | Paladin | generic warhorse; class mount/quests absent | class quests/wiring absent | high | later |
| Undead | Hunter | pet models exist | Taming quest has no Undead row | medium | later |
| Gnome | Priest | no unique models | no class quests; no racials | low | 1 |
| Troll | Warlock | demon models exist | Voidwalker quest is Orc-only | low | 1 |
| Troll | Druid | **no Troll form models** | form quests exist | high | later |
| Human | Hunter | pet models exist | Taming quest has no Human row | medium | later |
| Tauren | Paladin | generic kodo; class mount/quests absent | class quests/wiring absent | high | later |
| Night Elf | Mage | no unique models | none | low | later |
| Dwarf | Mage | no unique models | none | low | 1 |
| Blood Elf | Warrior | no unique models | none | low | 1 |
| Orc | Mage | no unique models | none | low | 1 |
| Dwarf | Shaman | totem items exist | totem quests absent; Bloodlust/Heroism | medium | later |

Starting zones are the race's existing zone: Coldridge for Dwarf and Gnome, Valley of Trials for Orc
and Troll, Northshire for Human, Shadowglen for Night Elf, Deathknell for Undead, Red Cloud Mesa for
Tauren, and Eversong for Blood Elf. The proposal reuses those positions; it does not add Ascension's
new starting subzones.

The archived Phase 3 snapshot of the Bronzebeard article
(`ascension.gg/news/bronzebeard-classic-og-9-classes-phase-3`) names only Troll Druid in text and
shows the other pairs in art. Its one class-specific note is that Troll Druid shapeshift forms are
customizable by hair and facial features; that is exactly the asset our client lacks. The later
official article adds Undead Paladin, Undead Hunter, Troll Warlock, and Gnome Priest. The twelve-pair
list is from <https://project-ascension.fandom.com/wiki/Race_Class_Combos>. Orc Mage, Dwarf Mage, and
Undead Hunter are on it; Gnome Hunter is not. The known Gnome Hunter example is a Turtle WoW pair.
The owner must confirm the canonical list and the batch in
[OPEN-QUESTIONS.md](../../decisions/OPEN-QUESTIONS.md).

### Contract

These rules stay in force until the RFC is accepted and folded into a spec or ADR:

1. A pair ships only when the client `CharBaseInfo.dbc` row and the server `playercreateinfo` row
   land in the same release.
2. The client change is a late-loading, whole-file DBC replacement; the server data is re-applicable
   custom SQL. Neither side is hand-edited in the live client or database.
3. A pair is eligible only after the full audit: client gate, server row, starting outfit, action
   bar, weapon skills, trainer, class quests, and class assets.
4. Only Blizzard 3.3.5 assets are reused. Ascension models, textures, forms, mounts, totems, and
   article prose are not copied.
5. New custom IDs are reserved in `runbook/database/id-registry.md` before use. This RFC uses only
   the DBC row blocks below.
6. A batch is accepted only after the test plan passes and the server and client logs are clean.
7. The target list and batch scope are owner decisions, not RFC decisions; see OPEN-QUESTIONS.

## Evidence

### Client gate: `CharBaseInfo.dbc`

Per-archive extraction of the installed bundle:

| Archive | `CharBaseInfo.dbc` | Notes |
|---------|--------------------|-------|
| `Data/enUS/locale-enUS.MPQ` | 62 rows, 145 B | effective source; contains `(8, 8)` Troll Mage; MD5 below |
| `Data/enUS/patch-enUS.MPQ` | none | no file |
| `Data/enUS/patch-enUS-2.MPQ` | none | no file |
| `Data/enUS/patch-enUS-3.MPQ` | none | no file |
| `Data/patch-A.MPQ` | none | no file |
| `Data/patch-I.mpq` | none | no file |
| `Data/patch-X.MPQ`, `Data/patch-Y.MPQ`, `Data/patch-Z.MPQ` | none | no file |
| base `common`, `expansion`, `lichking`, `patch`, `patch-2`, `patch-3` | none | no file |

Effective source MD5: `53a3e06b8a527701668f6c020a2ddfa1`.

Stock 3.3.5a WotLK has **61** pairs. The effective file has **62**; the extra row is `(8, 8)` Troll
Mage. The source is therefore an Ascension-modified locale archive, not a clean stock client. The
patch is based on the effective 62-row file, and it keeps the Troll Mage row.

### Client gate: creation screen

The creation Lua that the bundle runs is **not** the stock extracted file and **not** `patch-A`:

- `patch-A.MPQ` has no `Interface\GlueXML` entries; hash lookup returns no `CharacterCreate.lua`.
- `client_patch.py which` reports the winner as `Data/patch-I.mpq` (Reforged interface), with the chain
  `locale-enUS` → `patch-enUS` → `patch-enUS-2` → `patch-I`.
- The effective `patch-I` `CharacterCreate.lua` is 54,631 bytes (MD5
  `c7b1f8d5f0a46ed98e3475f5375d5d12`). It calls `GetAvailableClasses()` and gates buttons with
  `IsRaceClassValid(CharacterCreate.selectedRace, index)` at line 598. It also calls
  `UpdateCustomizationScene()` for the model.

`ChrRaces.dbc` has 21 rows (the ten playable races plus NPC races) and `ChrClasses.dbc` has ten class
rows (1-9 plus class 11 Druid). All proposed races and classes are present; no new race or class row
is needed.

The client-bundle runbook now records `patch-I` as the measured glue winner; the earlier attribution
to `patch-A` was wrong. The creation-screen claim in this RFC is based on `patch-I`, the file the
bundle runs.

### Creation preview and `CharStartOutfit.dbc`

The client binary loads `DBFilesClient\CharStartOutfit.dbc`; the effective client source is
`Data/enUS/patch-enUS-2.MPQ` (126 rows, 37,317 bytes, MD5
`b5352f5436a14a5ac50503e50b581fa4`). The server `DataDir/dbc/CharStartOutfit.dbc` is byte-identical.

`patch-I`'s Lua does not name `CharStartOutfit`; the model work is the opaque engine call
`UpdateCustomizationScene()`, and the creation screen has `CharCreatePreviewFrame` model previews.
The known All-Races-All-Classes implementation ships `CharStartOutfit.dbc` in its client patch for
3D creation previews. We cannot prove from Lua that the preview reads the table, so treat it as
preview-relevant: add the eight rows to the **client** patch and add an explicit preview test. If
the preview turns out not to use it, the rows are still needed for the server starting kit and are
harmless.

### Server gate

There is no `CharBaseInfo` reference anywhere under `src/` or in the project data. The server loads
`playercreateinfo` in `ObjectMgr::LoadPlayerInfo` (`src/server/game/Globals/ObjectMgr.cpp:4360`) and
refuses an invalid pair in `Player::Create` (`Player.cpp:499`). The table has 62 rows; none of the
proposed pairs is present. A pre-existing Troll Mage row exists but is not a proposed pair.

The other create tables are:

- `playercreateinfo_action`: 283 rows; class actions use `action` spell IDs and `type = 0`;
- `playercreateinfo_item`: one placeholder row only;
- `playercreateinfo_skills`: 77 rows; class rows use `classMask`, race rows `raceMask`, and the loader
  also requires `GetSkillRaceClassInfo(skill, race, class)` to return a row;
- `playercreateinfo_cast_spell`: two rows; the Warrior Battle Stance row (`classMask = 1`,
  `raceMask = 0`) already applies to any Warrior;
- `playercreateinfo_spell_custom`: empty; `PlayerStart.CustomSpells` defaults to false.

Starting spells come from `mod-auto-learn-spells`, which learns the union of class trainer spells at
login and level-up through the core `Trainer::CanTeachSpell` filter. That filter calls
`Player::IsSpellFitByClassAndRace`, which reads `SkillLineAbility.dbc` masks and
`SkillRaceClassInfo.dbc`.

### Trainers and starting zones

Base AC data spawns generic class trainers in every starting area: creature entries `26324-26332`,
`npcflag = 48`, faction 35, mapped through `creature_default_trainer` to a class trainer with
`Requirement = class`.

| Class | Generic creature | Trainer id | Spawns / zones |
|-------|------------------|------------|----------------|
| Mage | 26326 | 16 | 24 / 16 |
| Priest | 26328 | 11 | 24 / 16 |
| Warlock | 26331 | 31 | 22 / 15 |
| Warrior | 26332 | 1 | 24 / 16 |

Each generic trainer has 22-24 spawn clusters across maps 0, 1, and 530 and 15-16 zones. The six
starting areas are a subset: Coldridge (132), Northshire (9), Valley of Trials (363), Deathknell
(154), Shadowglen (256), and Red Cloud Mesa (221). The same entries also cover Elwynn (12), Durotar
(14), Tirisfal (85), Teldrassil (141), Mulgore (215), Eversong (3430), Azuremyst (3524), and the
capitals (Undercity 1497, Stormwind 1519, Ironforge 1537, Orgrimmar 1637, Thunder Bluff 1638,
Darnassus 1657, Silvermoon 3487, Exodar 3557). No new trainer NPC is needed for the proposed pairs.
`Trainer::IsTrainerValidForPlayer` checks class only, not race, so any class trainer works.

### Class assets and progression

| Class | Asset/progression check | Batch verdict |
|-------|-------------------------|---------------|
| Mage | casting anims exist; portals are spell visuals | eligible |
| Priest | casting anims exist; no unique model | eligible; no racials |
| Warlock | demon models are race-independent; Imp is trainer spell 688 | eligible; Voidwalker quest needs Troll |
| Warrior | plate/melee anims exist; Battle Stance is already cast at creation | eligible; weapon skills need DBC rows |
| Druid | `DruidCat`, `DruidBear`, `DruidCatTauren` exist; **no Troll forms** | out |
| Paladin | generic warhorse/kodo models exist; class mount wiring absent | out |
| Shaman | totem items exist; totem quest chain absent | out |
| Hunter | pet models exist; Taming chain has no Human/Undead row | out |

Death Knight is already open to all ten races and is not on the Ascension list; runeforging and the
Ebon Hold start need no new pairing. Warrior stances are trainer/creation data, not models.

### Weapon-skill matrix

Current loader result per proposed pair. Cell format is
`playercreateinfo_skills(row) -> SkillRaceClassInfo(id)`; `-` means no matching row. Skills 95
(Defense) and 162 (Unarmed) are included because a missing one would ship a character that never
skills up.

| Skill | Dwarf Mage 3/8 | Orc Mage 2/8 | Gnome Priest 7/5 | Troll Warlock 8/9 | Blood Elf Warrior 10/1 |
|-------|----------------|--------------|------------------|-------------------|------------------------|
| 43 Swords | - | - | - | - | - (add 950300) |
| 44 Axes | - | - | - | - | - (add 950301) |
| 45 Bows | - | - | - | - | - |
| 46 Guns | - | - | - | - | - |
| 54 Maces | - | - | 0/1107->135 | - | 0/1107->637 |
| 55 Two-Handed Swords | - | - | - | - | 0/35->626 |
| 95 Defense | 0/0->4 | 0/0->4 | 0/0->4 | 0/0->4 | 0/0->4 |
| 136 Staves | 0/1488->138 | 0/1488->138 | 0/1488->138 | 0/1488->138 | - |
| 160 Two-Handed Maces | - | - | - | - | - |
| 162 Unarmed | 0/0->6 | 0/0->6 | 0/0->6 | 0/0->6 | 0/0->6 |
| 172 Two-Handed Axes | - | - | - | - | - (add 950302) |
| 173 Daggers | - | - | - | 735/1293->129 | - (add 950303) |
| 176 Thrown | - | - | - | - | 0/9->640 |
| 226 Crossbows | - | - | - | - | - |
| 228 Wands | 0/400->144 | 0/400->144 | 0/400->144 | 0/400->144 | - |
| 229 Polearms | - | - | - | - | - |
| 433 Shield | - | - | - | - | 0/67->246 |
| 473 Fist Weapons | - | - | - | - | - |

Reading the matrix:

- Defense (95) and Unarmed (162) are present for all five pairs.
- Blood Elf Warrior has the only combo-specific weapon gaps: Swords, Axes, Two-Handed Axes, Daggers.
  The `playercreateinfo_skills` rows already include Blood Elf Warrior; the SCRI rows are absent.
  Four `skillraceclassinfo_dbc` rows fix it.
- Two-Handed Maces (160) is absent for Blood Elf Warrior **and** Orc Warrior because the base
  `playercreateinfo_skills` row is `1061/3` (Human, Dwarf, Tauren, Draenei). It is a base race-mask
  restriction, not a Blood Elf regression; do not add it in batch 1.
- Every other `-` is also absent for the existing same-class reference race (Gnome Mage, Undead
  Mage, Dwarf Priest, Orc Warlock). They are base class/race table gaps, not new regressions.
- Language/racial rows in 40-115 are expected: Dwarf Mage 98/101/111, Orc Mage 109, Gnome Priest 98,
  Troll Warlock 109, Blood Elf Warrior 109. No combo-specific language gap.

The 40-115 non-weapon rows:

| Skill | Dwarf Mage | Orc Mage | Gnome Priest | Troll Warlock | BE Warrior |
|-------|------------|----------|--------------|---------------|------------|
| 98 Common | 1101/0->40 | - | 1101/0->40 | - | - |
| 101 Dwarven Racial | 4/0->68 | - | - | - | - |
| 109 Orcish | - | 690/0->48 | - | 690/0->48 | 690/0->48 |
| 111 Language: Dwarven | 4/0->44 | - | - | - | - |
| 113 Language: Darnassian | - | - | - | - | - |
| 115 Language: Taurahe | - | - | - | - | - |

Racial rows outside 40-115 (125, 313, 315, 733, 753, 756) are present for the matching race and are
not shown.

`Flags 128` in the copied rows is `SKILL_FLAG_INCLUDE_IN_SORT` (0x80), not
`SKILL_FLAG_ALWAYS_MAX_VALUE` (0x10). `SkillTierID 0` is safe only because `SkillTiers.dbc` has no id
0 and the matching `playercreateinfo_skills` rows have `rank = 0`; `LearnDefaultSkill` only
dereferences the tier on the `SKILL_RANGE_RANK` path after `if (!rank) break;`. Never give one of
these rows a nonzero rank with tier 0.

### Starting outfits

`CharStartOutfit.dbc` has 126 rows. The effective table is also modified: it already contains
Dwarf Mage `(3, 8)` (rows 35 male, 52 female), which stock WotLK does not. Use the effective 126-row
source, not a clean stock table. Among the proposed pairs, only Dwarf Mage has a row; Orc Mage,
Gnome Priest, Troll Warlock, and Blood Elf Warrior have none. The server would start them with no
outfit, and the creation preview may show no class gear.

Copy the full 296-byte source row (item IDs, display IDs, and inventory slots), not only the item
columns, so the client preview has the same data as the server:

| New pair | Source rows (male, female) |
|----------|----------------------------|
| Orc Mage | Undead Mage `(5, 8)` id 34, 61 |
| Gnome Priest | Human Priest `(1, 5)` id 11, 38 |
| Troll Warlock | Orc Warlock `(2, 9)` id 20, 46 |
| Blood Elf Warrior | Orc Warrior `(2, 1)` id 2, 41 |

## DBC patch plan

### Rows and counts

`CharBaseInfo.dbc`:

- source: `Data/enUS/locale-enUS.MPQ`, 62 rows, 145 bytes, MD5
  `53a3e06b8a527701668f6c020a2ddfa1`;
- add `(2, 8)`, `(3, 8)`, `(7, 5)`, `(8, 9)`, `(10, 1)`;
- keep all 62 existing rows, including `(8, 8)`;
- result: 67 rows, 155 bytes (20-byte header + 67 × 2 + 1-byte string block);
- sort by RaceID, ClassID; keep the field count 2 and record size 2.

`CharStartOutfit.dbc`:

- source: `Data/enUS/patch-enUS-2.MPQ`, 126 rows, 37,317 bytes, MD5
  `b5352f5436a14a5ac50503e50b581fa4`;
- add eight rows (four pairs × two genders), IDs `950200-950207`, copied from the source rows above;
- result: 134 rows, 39,685 bytes, 77 fields, 296-byte records, 1-byte string block;
- keep the header field count and record size; copy the full source row, changing only ID, RaceID,
  ClassID, and SexID.

Record-size check: `CharStartOutfit` has 77 **declared** fields but 296-byte physical rows. The
format is `dbbbX` + 24 `i` + 48 `x`; `b` and `X` are one byte, `d` is the sort field, `x` is four:
4 + 3×1 + 1 + 24×4 + 48×4 = 296. Do **not** use `field_count * 4` (308); that assumes every field
is four bytes, ignores the byte fields and padding, and misaligns every row. The source header,
the file length, and `DBCFileLoader` all agree on 296. Assert `fields == 77`,
`record_size == 296`, and `len(data) == 20 + rows * record_size + string_size` before packing.

### Source archives

Only `locale-enUS.MPQ` carries `CharBaseInfo.dbc` in the installed bundle. It has 62 rows because
it is Ascension-modified; the stock table is 61. `patch-enUS`, `patch-enUS-2`, `patch-enUS-3`,
`patch-A`, `patch-I`, `patch-X`, and `patch-Y` do not carry it. The patch is based on the effective
62-row file.

`CharStartOutfit.dbc` is carried by `locale-enUS.MPQ`, `patch-enUS.MPQ`, and `patch-enUS-2.MPQ`;
`patch-enUS-2` wins. The server DataDir file matches `patch-enUS-2`. No other installed archive
carries it.

### Whole-file replacement and archive

An MPQ patch cannot carry a diff. `patch-V.MPQ` contains both complete tables at:

```text
DBFilesClient\CharBaseInfo.dbc
DBFilesClient\CharStartOutfit.dbc
```

A tested build produced 155-byte and 39,685-byte DBCs, 2 files, MPQ v1, zlib, listfile and
attributes present. The build recipe is
[runbook/development/client-dbc-patch.md](../../runbook/development/client-dbc-patch.md). The
artifact lives at
[`data/client-patches/race-class-combos/dist/patch-V.MPQ`](../../data/client-patches/race-class-combos/README.md):
6,098 bytes, SHA256
`66a5391889739e1cc0cfee1dc1a52da38986f3de1e2732c3e85b2a50c4afa460`; the directory has `build.py`,
`manifest.json`, `README.md`, and `LEDGER.md`.

### Load order

Measured with the client-patch tool:

- `CharBaseInfo.dbc`: winner `locale-enUS.MPQ`, sources only that archive.
- `CharacterCreate.lua`: winner `patch-I.mpq`; chain locale-enUS → patch-enUS → patch-enUS-2 →
  patch-I.
- `CharStartOutfit.dbc`: winner `patch-enUS-2.MPQ`; chain locale-enUS → patch-enUS → patch-enUS-2.
- `SkillTiers.dbc`: winner `locale-enUS.MPQ`, 26 rows, no id 0.

ADR-027 (parallel `feat/map-poi` branch, not merged here) records the English order: locale
non-patch, locale numeric patches, locale alphabetic patches, base non-patch, base numeric patches,
base alphabetic patches. The measured project tail low to high is:

```text
locale-enUS -> patch-enUS -> patch-enUS-2 -> patch-enUS-3
-> common -> common-2 -> expansion -> lichking
-> patch -> patch-2 -> patch-3
-> patch-A -> B, C, D, E, G, I, M, N, P, U -> patch-V -> patch-X -> patch-Y -> patch-Z
```

All of `patch-X`, `patch-Y` and `patch-Z` are installed. A root `patch-V.MPQ` is a base alphabetic
patch: it loads after `patch-U` and before `patch-X/Y/Z`, so it outranks `locale-enUS` and every
Reforged archive.

The installed Reforged set is exactly `patch-B`, `patch-C`, `patch-D`, `patch-E`, `patch-G`,
`patch-I`, `patch-M`, `patch-N`, `patch-P`, `patch-U` (ten archives; `patch-S` was removed). The
installed `patch-X` carries only `DBFilesClient\Item.dbc` (1 file), `patch-Y` carries only goblin
male model files (36 files), and `patch-Z` carries the `ServerMapPOI` addon and a `WorldMapFrame.lua`
override; none carries `CharBaseInfo.dbc` or `CharStartOutfit.dbc`.

Fallback: if a client shape puts the locale chain last (the Russian/Chinese shape in ADR-027), or if a
later project archive wins, move the DBC to the highest-priority locale alphabetic archive (for
example `patch-enUS-Z.mpq`) or into that winning archive. Verify with `client_patch.py which` before
shipping. Never ship two carriers of the same DBC.

The project family is not merged in this branch. The RFC cites ADR-027 as an external reference and
proposes `patch-V` as the character-creation DBC carrier; the client-patch owner must approve that
carrier.

## Server data plan

### `playercreateinfo`

Insert five rows, copying the race's existing start position:

| Race | Class | Map | Zone | X | Y | Z | Orientation |
|------|-------|-----|------|---|---|---|-------------|
| 2 | 8 | 1 | 14 | -618.518 | -4251.67 | 38.718 | 0 |
| 3 | 8 | 0 | 1 | -6240.32 | 331.033 | 382.758 | 6.17716 |
| 7 | 5 | 0 | 1 | -6240 | 331 | 383 | 0 |
| 8 | 9 | 1 | 14 | -618.518 | -4251.67 | 38.718 | 0 |
| 10 | 1 | 530 | 3431 | 10349.6 | -6357.29 | 33.4026 | 5.31605 |

### `playercreateinfo_action`

| Race | Class | Button | Action | Type | Note |
|------|-------|--------|--------|------|------|
| 2 | 8 | 0, 1, 2 | 133, 168, 33702 | 0 | 33702 is the spell-damage Blood Fury; 20572 is AP |
| 3 | 8 | 0, 1, 2, 3 | 133, 168, 20594, 2481 | 0 | Dwarf racial buttons |
| 7 | 5 | 0, 1, 2 | 585, 2050, 20589 | 0 | Gnome racial |
| 8 | 9 | 0, 1, 2 | 686, 687, 26297 | 0 | Troll racial |
| 10 | 1 | 72, 73, 74, 84, 96 | 6603, 78, 28730, 6603, 6603 | 0 | copy the existing warrior block |

Orc casters use the spell-damage Blood Fury (33702), not melee/ranged `20572` or the shaman mixed
`33697`. The warrior block keeps the existing buttons 72/73/74/84/96.

### `CharStartOutfit.dbc`

Deploy the same 134-row file from the client patch to `DataDir/dbc/CharStartOutfit.dbc`. Leave
`charstartoutfit_dbc` empty; the server and client then use identical bytes. If a deployment cannot
replace DataDir, the DB override can carry the eight item rows as a fallback, but the client preview
still needs the DBC.

### `skillraceclassinfo_dbc`

Add four rows for Blood Elf Warrior, IDs `950300-950303`:

| ID | SkillID | RaceMask | ClassMask | Flags | MinLevel | SkillTierID | SkillCostIndex |
|----|---------|----------|-----------|-------|----------|-------------|----------------|
| 950300 | 43 (Swords) | 512 | 1 | 128 | 0 | 0 | 0 |
| 950301 | 44 (Axes) | 512 | 1 | 128 | 0 | 0 | 0 |
| 950302 | 172 (Two-Handed Axes) | 512 | 1 | 128 | 0 | 0 | 0 |
| 950303 | 173 (Daggers) | 512 | 1 | 128 | 0 | 0 | 0 |

Flags 128 is `SKILL_FLAG_INCLUDE_IN_SORT`. Tier 0 is safe only with rank 0; see the note above.

### Quests

Troll Warlock: extend the Orc Voidwalker chain, including the breadcrumb, to Trolls:

```sql
UPDATE quest_template
SET AllowableRaces = AllowableRaces | 128
WHERE ID IN (1501, 1504, 1506) AND (AllowableRaces & 128) = 0;
```

Quest 1506 "Gan'rul's Summons" (giver Ophek, `RewardNextQuest = 1501`) is the lead-in; without it a
Troll gets the chain without the starting breadcrumb. Quest 1501 "Creature of the Void" and 1504 "The
Binding" are given by Gan'rul Bloodeye in Orgrimmar (creature 5875). The Succubus chain (`1476`,
`1512`, `1513`) already has `AllowableRaces = 690`; Felhunter `1795` is open to all races.

### SQL shape and idempotency

The implementation belongs in `data/sql/custom/db_world/race_class_combos.sql` (re-applicable, not
applied in this proposal):

- `DELETE` the five `playercreateinfo` pairs, then `INSERT` them;
- `DELETE` the action rows for the five pairs, then `INSERT` them;
- `DELETE` `skillraceclassinfo_dbc` IDs `950300-950303`, then `INSERT`;
- run the guarded `quest_template` update once; it is naturally idempotent.

No `playercreateinfo_spell_custom`, `playercreateinfo_item`, or `playercreateinfo_skills` rows are
needed. No new creature, item, spell, quest, or gameobject IDs are used. The outfit rows live in the
DBC, not SQL.

## Rollout order

1. Owner answers the target list, batch, Gnome Priest racial, and Troll quest questions in
   OPEN-QUESTIONS.
2. Build `patch-V.MPQ` with the runbook recipe; record source and output SHA256.
3. Land the server SQL; apply it to the local DB by restarting the worldserver.
4. Install the client patch on a test client; clear `Cache`.
5. Run the test plan.
6. Only then update the supported client bundle and the live realm.

If the server rows and the client patch ship separately, the failure mode is an absent class button
(server rows first) or a refused creation (client patch first).

## Test plan

Static:

- DBC check: `CharBaseInfo` 67 rows/155 bytes, five pairs present, all 62 effective rows retained;
- DBC check: `CharStartOutfit` 134 rows/39,685 bytes, 77 fields, **296-byte** records (not
  `field_count * 4`), eight new rows with the copied display/slot data, no duplicate
  race/class/gender;
- SQL lint: `python apps/codestyle/codestyle-sql.py`;
- docs: `make verify-docs`; whitespace: `git diff --check`.

Local stack:

- restart the worldserver; confirm `Loaded 67 Player Create Definitions` and no `sql.sql` errors;
- confirm the five `playercreateinfo` rows and the action rows exist;
- install the client patch; run `client_patch.py which` and confirm `patch-V` wins both DBCs;
- create each pair on the patched test client; confirm the class button and creation succeed;
- confirm spawn map/zone/position, starting outfit, action bar, and level-1 spellbook;
- confirm the creation preview shows the class-appropriate starting gear (compare with the same-class
  source race); record whether the preview changes if the outfit rows are absent;
- open the class trainer in the starting area and the capital; confirm the level-1 spells are listed;
- class-specific checks:
  - Dwarf Mage: Fireball, Frost Armor, Stoneform; at 40, Teleport: Ironforge;
  - Orc Mage: Fireball, Frost Armor, spell-damage Blood Fury (33702); at 40, Teleport: Orgrimmar;
  - Gnome Priest: Smite, Lesser Heal, Escape Artist; note the absence of priest racials;
  - Troll Warlock: Summon Imp; at 10 take 1506 → 1501 → 1504 from the Orc chain; at 20 Succubus;
    at 30 Felhunter;
  - Blood Elf Warrior: Battle Stance, Heroic Strike, Arcane Torrent; action buttons 72/73/74/84/96;
    equip a sword, axe, two-handed axe, and dagger and confirm the skills appear and attacks work;
- confirm Defense (95) and Unarmed (162) are in the skill list for all five;
- regression: create a stock combo with the patched client; log in an existing character; no crash or
  glue Lua error;
- logs: server `Server.log` and `Errors.log` clean; client logs clean; no `ERROR #132`.

## Open questions and risks

1. **Canonical list.** The wiki's twelve pairs are the proposal; the owner must confirm. Gnome Hunter
   is a Turtle WoW pair, not an Ascension one. See OPEN-QUESTIONS.
2. **Batch scope.** The five-pair batch is a recommendation. See OPEN-QUESTIONS.
3. **Gnome Priest racials.** No racial spells; options are in OPEN-QUESTIONS.
4. **Troll Warlock quest shape.** Extend 1501/1504/1506 or add a Troll chain; see OPEN-QUESTIONS.
5. **Client patch carrier.** `patch-V` is outside the client-patch branch's X/Y/Z family; the
   client-patch owner must approve it. ADR-027 is an external, unmerged reference.
6. **Creation preview.** The engine call is opaque; the eight outfit rows are shipped in the client
   patch and the preview is tested. If the preview ignores them, the server still needs them.
7. **Client distribution.** Only patched clients can create the new pairs. A stock client can play
   existing characters but cannot create a batch pair.
8. **Animation coverage.** The five races already have casting or melee animation sets; the creation
   preview and combat test must confirm cast, melee, and two-hand animations.
9. **Balance.** Orc Mage (Blood Fury), Troll Warlock (Berserking), Dwarf Mage (Stoneform), Gnome
   Priest (Escape Artist), and Blood Elf Warrior (Arcane Torrent) create new synergy. No tuning in
   batch 1.
10. **Licensing.** The pair list is factual data. Ascension prose and custom models/textures are not
    copied. Batch 1 uses only Blizzard 3.3.5 assets.
11. **Pre-existing Troll Mage.** The effective client and server both allow `(8, 8)` Troll Mage; keep
    it. It is not a proposed pair and not a regression.
12. **RFC number.** RFC-004 and RFC-006 exist on parallel branches; renumber at merge if 007
    collides.

## Decision record

Pending. On acceptance, fold the final pair list, batch order, and the two-gate release rule into
[ADR-035](../../decisions/ADR-035-race-class-combos.md) and `specs/content-pipeline.md`, then move this
RFC to `rfcs/archived/`.
