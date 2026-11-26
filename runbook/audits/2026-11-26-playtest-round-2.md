# Playtest — 2026-11-26, round 2

> **Superseded 2026-11-27.** The general map POI layer described here was withdrawn
> ([ADR-032](../../decisions/ADR-032-map-poi-layer.md) → [ADR-037](../../decisions/ADR-037-world-map-pins.md)).
> The client patch is now `map-pins`; only the Call Board and world-boss checks remain valid, and
> the counts below are stale. This file is kept as a record.

Server from `/Users/gasman/wow/azerothcore`; client from `~/Games/wotlk-clean`. Report each step as
PASS, FAIL, or FAIL + what you saw. For a Lua error, send the first error block only.

The agent backed up the three databases (`var/backups/manual/20261126-231310/acore.sql`, sha256
`a4f7dca99ea7b2cda2f32128f9079e896351b7e1f30d61dcae7c7b93ab8b5bbe`) and restarted the
worldserver. The restart applied `call_boards.sql`. `acore-data` still reports four
`pending_db_world` revisions; they were pending before this batch and are not part of it.

## 0. Prep

1. `make status` — both servers up. If not, `make start`.
2. **Fully quit the client and restart it.** `patch-Z.MPQ` changed; `/reload` does not reload an MPQ.
3. Log in as an existing level-80 character first. No Lua error; bags and spells intact.

Expected at login, in chat:

```text
[client-patch] patch-Z.MPQ canary active: WorldMapFrame.lua loaded from patch-Z.
ServerMapPOI loaded from patch-Z.MPQ (583 static markers, Outlaw protocol v2 token required).
```

A missing first line means `patch-Z` lost the load order. A missing second line means the addon did
not load. If the number is **568** or **24**, the old patch is still loaded.

Check `env/dist/logs/Server.log` for `call_boards.sql` and no SQL error.

## 1. Map POIs — the main slice

| Step | Do | Expect |
|---|---|---|
| 1.1 | Stand in **Stormwind**, open the **Eastern Kingdoms continent map** | **no static pins in the ocean**; only the client's zone labels. Open and close it twice |
| 1.2 | Open the **Stormwind** zone map | **23 pins**; hover each. Flight master, innkeeper, battlemasters, meeting stone, two portals, Warpweaver, call board |
| 1.3 | Look at the pins | **12 px tracking glyphs**, not 18 px squares. Alliance blue, Horde red, shared gold |
| 1.4 | Hover a battlemaster | tooltip names the NPC, **not** "Flight master" |
| 1.5 | Open **Orgrimmar** | **25 pins**, red tint, no Alliance markers; call board present |
| 1.6 | Open **Shattrath** and **Dalaran** | **42** and **48** pins, gold tint, both factions' NPCs; Dalaran micro-map works |
| 1.7 | Find a **Warpweaver** in a capital | map icon, label "Warpweaver"; all ten cities |
| 1.8 | Hellfire Peninsula; Shadowmoon Valley | skull at Doom Lord Kazzak; skull at Doomwalker |
| 1.9 | Westfall Deadmines stone | label **The Deadmines**, note `(15-25)` |
| 1.10 | Burning Steppes Blackrock Depths stone | label **Blackrock Depths**, note `(47-83)` — not "Coren Direbrew" |
| 1.11 | Tirisfal Scarlet Monastery stone | label **Scarlet Monastery** — not "The Headless Horseman" |
| 1.12 | Hellfire Peninsula, a Hellfire Citadel stone | one of the four wings, not "Shattered Halls" for all |
| 1.13 | Stormwind mage tower, Blasted Lands portal | portal icon, label "Portal to Blasted Lands"; no dead instance pins |
| 1.14 | A **call board** in any capital | object name "Call Board" and the map POI; hover both. The board has no quest yet, by design |
| 1.15 | All 15 call-board cities | Stormwind, Ironforge, Darnassus, Exodar, Orgrimmar, Undercity, Thunder Bluff, Silvermoon, Shattrath, Dalaran, Booty Bay, Gadgetzan, Everlook, Area 52, Ratchet |
| 1.16 | Silvermoon and Everlook boards | board sits on the ground, no visible float or sink |
| 1.17 | Stand in Stormwind, open **Elwynn Forest** | **2 markers**: Innkeeper Farley and the Arena Battlemaster. **No flight master** — 3.3.5 has none; the flight point is a Cataclysm addition. No Stormwind pins |
| 1.17b | Still in Stormwind, open the **Ironforge** map | no Stormwind pins; the displayed map decides the zone, not the player's location |
| 1.18 | Silithus, Eastern Plaguelands, Hellfire, Nagrand, Wintergrasp, Zangarmarsh | translucent red overlay on each |
| 1.19 | Elwynn Forest, then the continent map | **no** red overlay |
| 1.20 | Stormwind emissary cluster | stacked pins fan out on a small ring; every pin is hoverable, none hidden |
| 1.21 | Open and close the map several times; `/reload` | no flicker, no Lua error, no growing frame count |
| 1.22 | If Questie is installed | its flight master/innkeeper/meeting-stone pins double the native ones. Disable Questie's townsfolk POIs and the native pins remain; no Lua error |

Explicitly **expected absent**: no ship or zeppelin markers, no continent-level pins. Both are
deliberate in this slice.

## 2. Cooldown error

| Step | Do | Expect |
|---|---|---|
| 2.1 | Track a quest item, or trigger the Call of Water path that errored before | no `Cooldown.lua` Lua error |
| 2.2 | `env/dist/logs/Errors.log` after the session | no new `CooldownFrame_SetTimer` lines |

## 3. Call boards in the world database

| Step | Do | Expect |
|---|---|---|
| 3.1 | Walk to any board, or `.go` to its coordinates | gameobject named "Call Board" near the innkeeper |
| 3.2 | Hover the board | no quest `!`; it is inert until the objectives slice |
| 3.3 | If a board is missing | check `Server.log` for `call_boards.sql`; the agent can query `gameobject` for ids `5714521-5714535` |

## 4. Regression — confirm the restart changed nothing else

| Step | Do | Expect |
|---|---|---|
| 4.1 | Character creation screen, one of each faction | renders, no crash, no white character |
| 4.2 | Your level-80 character | all previously learned spells still present |
| 4.3 | `.pledge status`; then a pledge change in Darnassus or Dalaran | accepted; outside a capital refused (previous batch) |
| 4.4 | Kill dungeon trash and a boss below max level | trash about 10%, boss about 33% |
| 4.5 | Complete a dungeon quest | about 6x the global 2x reward |
| 4.6 | Fresh low-level character | no auto-learned class spells; trainer sells them |
| 4.7 | Shaman totem chain, if available | Earth/Fire/Water/Air chains reachable; no vendor totem |
| 4.8 | `.treasure list`, `.treasure preview 901001`, `.treasure clear` | unchanged |
| 4.9 | Journal, any dungeon card | opens, bosses listed |
| 4.10 | `env/dist/logs/Errors.log` | no new lines beyond the stock `trainer_spell ... is a talent` ones |

## Result template

```text
0  prep / canary:            PASS/FAIL
1  map POIs (note which):    PASS/FAIL ...
2  cooldown:                 PASS/FAIL
3  call boards (city):       PASS/FAIL ...
4  regression:               PASS/FAIL ...
Lua errors: <first error only>
```

## Not in this batch

- Ships and zeppelins on the map; continent-level pins. Deliberate, see 1.
- A Goldshire flight master. 3.3.5 has none; adding one is custom content, not a fix.
- FrameXML migration, the branded Questie build, and the other addon patches. Separate session.
- The call-board menu/objectives engine; the boards are inert.
- High Risk death chest, Bloodforged drops, PvP mode GUI, white Journal boss models, Mythic+.
