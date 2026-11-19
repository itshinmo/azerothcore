# Manual solo instance runs — checklist and results

The owner runs every dungeon and raid solo on a cheated level-80 character; see
`.ai/memories/status.md` task 9 and [ADR-017](../../decisions/ADR-017-bot-rig-paused.md). This page
is the checklist and the result record. The instance list matches the GM Helper addon Instances tab
exactly (`tools/gm-addon/GMHelperInstances.lua`, generated from `LFGDungeons.dbc` plus the vanilla
sub-wings it omits).

Checked entries are already covered: `bots` means the playerbot rig cleared the instance and the
result is recorded in the [bot ledger](2026-11-17-bot-dungeon-runs.md). Unchecked entries are the
manual work. Tick an entry only after a run with a recorded result below.

## How to run

1. `make start`, log in with the ADMIN account, character level 80.
2. On the mage, toggle the solo cheats (GM Helper **Self** tab or chat):
   `.gm on`, `.cheat god`, `.cheat power`, `.cheat cooldown`, `.cheat casttime`,
   `.modify speed 2`. Reveal maps with `.cheat explore 1`.
3. GM Helper **Instances** tab → click the instance to teleport to its entrance
   (`.go xyz` from `areatrigger_teleport`). For lockouts: `.instance unbind all <own name>`.
4. Note anything broken per run; findings go through
   [runbook/operation/bug-reports.md](../operation/bug-reports.md) (logs in `env/dist/logs/`,
   data fixes in `data/sql/updates/pending_db_*`, upstream check for code causes).
5. Record: date, instance, result (clear / partial / blocked), findings. Append under the
   Results section.

## Classic — Dungeons (26)

- [x] Blackfathom Deeps — manual clear 2026-11-19, no findings (the rig's F3c/F3d harness defects
      do not apply to a human run).
- [x] Blackrock Depths - Prison — bots cleared both routes (`brd-uc` 17/17, `brd-db` 9/9 replay).
- [x] Deadmines — bots.
- [x] Dire Maul - East — bots (`dm-east`).
- [x] Dire Maul - North — bots (`dm-north`).
- [x] Dire Maul - West — bots (`dm-west`).
- [x] Gnomeregan — bots.
- [x] Lower Blackrock Spire — bots (replay after F1 fix).
- [x] Maraudon - Orange Crystals — bots (`mara-orange`).
- [x] Maraudon - Purple Crystals — bots (`mara-pw`, `mara-purple`).
- [x] Ragefire Chasm — bots.
- [x] Razorfen Downs — bots.
- [x] Razorfen Kraul — bots.
- [x] Scarlet Monastery - Armory — bots.
- [x] Scarlet Monastery - Cathedral — bots.
- [x] Scarlet Monastery - Graveyard — bots.
- [x] Scarlet Monastery - Library — bots.
- [x] Scholomance — bots.
- [x] Shadowfang Keep — bots.
- [x] Stormwind Stockade — bots.
- [x] Stratholme - Main Gate — bots (13/13).
- [x] Stratholme - Service Entrance — optional; the Main Gate run cleared 13/13.
- [x] Sunken Temple — bots.
- [x] Uldaman — bots.
- [x] Wailing Caverns — bots.
- [x] Zul'Farrak — bots.

## Classic — Raids (6)

All unchecked except UBRS: the 2026-11-19 bot batch wiped (`ony`, `mc`) or was aborted before
progress (`bwl`, `zg`, `aq20`, `aq40`); results are historical, not coverage (ADR-016/ADR-017).

- [ ] Ahn'Qiraj Ruins (AQ20)
- [ ] Ahn'Qiraj Temple (AQ40)
- [ ] Blackwing Lair
- [ ] Molten Core
- [x] Upper Blackrock Spire — bots cleared it as a dungeon token (`ubrs` 8/8); the addon lists it
      as a raid because `LFGDungeons.dbc` does.
- [ ] Zul'Gurub

## The Burning Crusade — Dungeons (16)

Never bot-run (batch cancelled). All manual.

- [ ] Auchenai Crypts
- [ ] Blood Furnace
- [ ] Hellfire Ramparts
- [ ] Mana-Tombs
- [ ] Sethekk Halls
- [ ] Shadow Labyrinth
- [ ] Shattered Halls
- [ ] Slave Pens
- [ ] The Arcatraz
- [ ] The Black Morass
- [ ] The Botanica
- [ ] The Escape From Durnholde
- [ ] The Mechanar
- [ ] The Steamvault
- [ ] Underbog
- [ ] Magisters' Terrace

## The Burning Crusade — Raids (9)

Never bot-run. All manual.

- [ ] Black Temple
- [ ] Gruul's Lair
- [ ] Hyjal Past
- [ ] Karazhan
- [ ] Magtheridon's Lair
- [ ] Serpentshrine Cavern
- [ ] Tempest Keep
- [ ] The Sunwell
- [ ] Zul'Aman

## Wrath of the Lich King — Dungeons (16)

Never bot-run (batch cancelled). All manual.

- [ ] Ahn'kahet: The Old Kingdom
- [ ] Azjol-Nerub
- [ ] Drak'Tharon Keep
- [ ] Gundrak
- [ ] Halls of Lightning
- [ ] Halls of Reflection
- [ ] Halls of Stone
- [ ] Pit of Saron
- [ ] The Culling of Stratholme
- [ ] The Forge of Souls
- [ ] The Nexus
- [ ] The Oculus
- [ ] Trial of the Champion
- [ ] Utgarde Keep
- [ ] Utgarde Pinnacle
- [ ] Violet Hold

## Wrath of the Lich King — Raids (9)

All unchecked.

- [ ] Icecrown Citadel
- [ ] Naxxramas
- [ ] Onyxia's Lair (3.3.5 rework; the `ony` bot wipe is historical)
- [ ] Ruby Sanctum
- [ ] The Eye of Eternity
- [ ] The Obsidian Sanctum
- [ ] Trial of the Crusader
- [ ] Ulduar
- [ ] Vault of Archavon

## Results

Append one line per run: `date | instance | result | findings`.

- 2026-11-19 | Blackfathom Deeps | clear | none reported; server logs clean (Errors.log empty, no
  exceptions)
