# Manual solo instance runs — checklist and results

The owner runs dungeons and raids solo on a cheated level-80 character; see
`.ai/memories/status.md` task 9 and [ADR-017](../../decisions/ADR-017-bot-rig-paused.md). This page
is the checklist and the result record. The instance list matches the GM Helper addon Instances tab
exactly (`tools/gm-addon/GMHelperInstances.lua`, generated from `LFGDungeons.dbc` plus the vanilla
sub-wings it omits).

**The sweep closed on 2026-11-20** ([ADR-019](../../decisions/ADR-019-instance-scope-closed.md)):
remaining unvisited instances are assumed functioning; a player ticket or bug report triggers a run.

Checked entries are already covered: `bots` means the playerbot rig cleared the instance and the
result is recorded in the [bot ledger](2026-11-17-bot-dungeon-runs.md). Unchecked entries marked
"assumed functioning (ADR-019)" have no scheduled run; others are the manual work. Tick an entry
only after a run with a recorded result below.

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

Sweep ended on 2026-11-20 after Shattered Halls per the owner's decision
([ADR-019](../../decisions/ADR-019-instance-scope-closed.md)): the remaining TBC and WotLK
dungeons and raids are **assumed functioning** until a player ticket or bug report triggers a run.
7 of 16 cleared manually, zero findings, zero server errors.

- [x] Auchenai Crypts — manual clear 2026-11-20, no findings; logs clean.
- [x] Blood Furnace — manual clear 2026-11-20, no findings; logs clean.
- [x] Hellfire Ramparts — manual clear 2026-11-20, no findings; logs clean.
- [x] Mana-Tombs — manual clear 2026-11-20, no findings; logs clean.
- [x] Sethekk Halls — manual clear 2026-11-20, no findings; logs clean.
- [x] Shadow Labyrinth — manual clear 2026-11-20, no findings; logs clean.
- [x] Shattered Halls — manual clear 2026-11-20, no findings; logs clean.
- [ ] Slave Pens — assumed functioning (ADR-019)
- [ ] The Arcatraz — assumed functioning (ADR-019)
- [ ] The Black Morass — assumed functioning (ADR-019)
- [ ] The Botanica — assumed functioning (ADR-019)
- [ ] The Escape From Durnholde — assumed functioning (ADR-019)
- [ ] The Mechanar — assumed functioning (ADR-019)
- [ ] The Steamvault — assumed functioning (ADR-019)
- [ ] Underbog — assumed functioning (ADR-019)
- [ ] Magisters' Terrace — assumed functioning (ADR-019)

## The Burning Crusade — Raids (9)

Never bot-run. Manual sweep ended before reaching raids; per
[ADR-019](../../decisions/ADR-019-instance-scope-closed.md) they are assumed functioning until a
player report triggers a run.

- [ ] Black Temple — assumed functioning (ADR-019)
- [ ] Gruul's Lair — assumed functioning (ADR-019)
- [ ] Hyjal Past — assumed functioning (ADR-019)
- [ ] Karazhan — assumed functioning (ADR-019)
- [ ] Magtheridon's Lair — assumed functioning (ADR-019)
- [ ] Serpentshrine Cavern — assumed functioning (ADR-019)
- [ ] Tempest Keep — assumed functioning (ADR-019)
- [ ] The Sunwell — assumed functioning (ADR-019)
- [ ] Zul'Aman — assumed functioning (ADR-019)

## Wrath of the Lich King — Dungeons (16)

Never bot-run (batch cancelled). Manual sweep ended before reaching WotLK dungeons; per
[ADR-019](../../decisions/ADR-019-instance-scope-closed.md) they are assumed functioning until a
player report triggers a run.

- [ ] Ahn'kahet: The Old Kingdom — assumed functioning (ADR-019)
- [ ] Azjol-Nerub — assumed functioning (ADR-019)
- [ ] Drak'Tharon Keep — assumed functioning (ADR-019)
- [ ] Gundrak — assumed functioning (ADR-019)
- [ ] Halls of Lightning — assumed functioning (ADR-019)
- [ ] Halls of Reflection — assumed functioning (ADR-019)
- [ ] Halls of Stone — assumed functioning (ADR-019)
- [ ] Pit of Saron — assumed functioning (ADR-019)
- [ ] The Culling of Stratholme — assumed functioning (ADR-019)
- [ ] The Forge of Souls — assumed functioning (ADR-019)
- [ ] The Nexus — assumed functioning (ADR-019)
- [ ] The Oculus — assumed functioning (ADR-019)
- [ ] Trial of the Champion — assumed functioning (ADR-019)
- [ ] Utgarde Keep — assumed functioning (ADR-019)
- [ ] Utgarde Pinnacle — assumed functioning (ADR-019)
- [ ] Violet Hold — assumed functioning (ADR-019)

## Wrath of the Lich King — Raids (9)

Never bot-run. Manual sweep ended before reaching WotLK raids; per
[ADR-019](../../decisions/ADR-019-instance-scope-closed.md) they are assumed functioning until a
player report triggers a run, including Onyxia's Lair (the level-80 rework; the `ony` bot wipe is
historical).

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
- 2026-11-20 | Auchenai Crypts | clear | none reported; logs clean (Server.log 0 ERROR/FATAL,
  Errors.log empty)
- 2026-11-20 | Blood Furnace | clear | none reported; logs clean
- 2026-11-20 | Hellfire Ramparts | clear | none reported; logs clean
- 2026-11-20 | Mana-Tombs | clear | none reported; logs clean
- 2026-11-20 | Sethekk Halls | clear | none reported; logs clean
- 2026-11-20 | Shadow Labyrinth | clear | none reported; logs clean; owner cleared the 5-instances-per-hour
  account limit themselves after Mana-Tombs (mechanism documented: `acore_characters.account_instance_times`,
  loaded at login, re-saved at logout — a delete only sticks when logged out)
- 2026-11-20 | Shattered Halls | clear | none reported; logs clean. Sweep ended here per the owner:
  the remaining TBC and WotLK instances are assumed functioning until a player ticket or bug report
  triggers a run ([ADR-019](../../decisions/ADR-019-instance-scope-closed.md))
