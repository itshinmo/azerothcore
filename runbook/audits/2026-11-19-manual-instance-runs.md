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

All cleared manually on 2026-11-19. The 2026-11-19 bot batch's `ony`/`mc` wipes and aborted
`bwl`/`zg`/`aq20`/`aq40` runs are historical (ADR-016/ADR-017), superseded by the manual results.

- [x] Ahn'Qiraj Ruins (AQ20) — manual clear 2026-11-19, no findings.
- [x] Ahn'Qiraj Temple (AQ40) — manual clear 2026-11-19, one blizzlike-behavior note: Viscidus
      cannot die to spells alone at the frozen stage (the kill gate requires the attacker to be
      auto-attacking — a solo caster stalls at 1%). Retail-intended melee-shatter mechanic,
      documented as intended, left untouched per the blizzlike-verification policy; finished with
      staff auto-attack during the freeze.
- [x] Blackwing Lair — manual clear 2026-11-19, one finding: the Chromaggus gate/lever encounter
      could not start (lever spawned usable but one-shot flag persistence + a GM `.respawn` of the
      boss re-immuned him mid-run; worked around with `.gobject add temp 179148`). World DB verified
      correct — retail lever flow intact for normal players; GM-respawn artifact only, no SQL fix
      needed.
- [x] Molten Core — manual clear 2026-11-19, no findings.
- [x] Upper Blackrock Spire — bots cleared it as a dungeon token (`ubrs` 8/8); the addon lists it
      as a raid because `LFGDungeons.dbc` does.
- [x] Zul'Gurub — manual clear 2026-11-19, two findings (both data quirks, no gameplay blocker):
      Edge of Madness rotation collapsed — all four game events share the same daily phase
      (14-day-spaced anchors with 24h occurence), so the brazier script always picks Gri'lek first
      and the other three spirits are unreachable; and Gurubashi Mojo Madness (19931) has no loot,
      vendor, or quest source anywhere in the DB, so players cannot obtain it without GM give.
      Encountered as GM-only content as shipped. Edge of Madness skipped (optional summon); main
      bosses cleared.

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
- 2026-11-19 | Molten Core | clear | none reported; logs clean
- 2026-11-19 | Blackwing Lair | clear | one finding: Chromaggus lever encounter could not start —
  boss spawns SetImmuneToAll(true) and the lever clears it once, but a GM `.respawn` of the boss
  re-applied the immunity and the lever's own NOT_SELECTABLE flag made it un-reusable; `.gobject
  add temp 179148` spawned a fresh lever that worked. DB verified correct (door state=1 closed,
  lever state=1 ready) — GM-respawn artifact, no data or code fix needed. Nefarian unaffected.
- 2026-11-19 | Zul'Gurub | clear | two data quirks: Edge of Madness rotation collapsed (all four
  game events share one daily phase; brazier always picks Gri'lek; other spirits unreachable) and
  Gurubashi Mojo Madness (19931) has no player-obtainable source. Edge of Madness skipped as
  optional/GM-only content.
- 2026-11-19 | Ahn'Qiraj Ruins (AQ20) | clear | none reported; logs clean
- 2026-11-19 | Ahn'Qiraj Temple (AQ40) | clear | one blizzlike note: Viscidus kill gate requires an
  auto-attacking attacker (spell-only kills stall at 1%) — retail-intended, left as-is per the
  blizzlike-verification policy; finished with staff auto-attack during the freeze. Also: the
  addon's blanket combat guard blocked `.combatstop` while in combat — fixed in GM Helper 0.4.3
  (chat commands are legal in combat).
