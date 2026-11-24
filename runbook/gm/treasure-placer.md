# Treasure placer (`.treasure`)

## When to use

You need to place, re-place, or verify a hand-placed world treasure chest
([ADR-031](../../decisions/ADR-031-world-treasures.md),
[specs/world-treasures.md](../../specs/world-treasures.md)). The tool previews a real chest in the
world without touching the database, then exports the final coordinates as SQL.

## Prerequisites

- A GM character whose account has the `content-tester` (`950101`) or `admin` (`950103`) project
  role. Both roles include permission `950152` through
  [gm_rbac_presets.sql](../../data/sql/custom/db_auth/gm_rbac_presets.sql).
- The account was granted the role **before** the current login. RBAC data loads at login, so a
  grant made while you are online does nothing until you relog.
- The `mod-treasure-placer` module is built; `.treasure` appears in the command list.
- Stand in the open world, not in an instance or battleground. `save` refuses both.

Grant the role if needed (server console or an admin character):

```text
.rbac account grant <account> 950101
```

Then relog.

## Commands

```text
.treasure list                 # items, chest entry and spawn GUID
.treasure preview <item>       # temporary chest 1.5 yards ahead, 10 minutes, no DB write
.treasure save <item>          # record the active preview's position and facing
.treasure export               # print SQL UPDATE lines for everything saved this session
.treasure clear                # remove the current preview
```

`.treasure preview` and `.treasure save` take the **item** id, not the chest entry: `901001` for the
Goldshire Ledger, not `930001`.

## Steps

1. `git status` clean and server running with the current build.
2. Stand 1.5 yards behind the spot where the chest should sit, facing it. The preview lands 1.5 yards
   in front of you, which puts it on the intended spot.
3. `.treasure preview 901001`
4. Look at the chest. It must sit on the floor, not in a wall, not floating, and be reachable by a
   normal character walking up to it.
5. Adjust your position and preview again until the chest is right.
6. `.treasure save 901001` — this stores the preview chest's position and orientation, not your feet.
   If the preview expired (10 minutes), was removed, or you changed map, save silently falls back to
   your standing position; preview again first.
7. Repeat 2-6 for each item you are fixing.
8. `.treasure export` and copy the output.
9. Put the values in **three** places:
   - the spawn `INSERT` tuple in
     [world_treasures_batch_01.sql](../../data/sql/custom/db_world/world_treasures_batch_01.sql):
     `map`, `position_x`, `position_y`, `position_z`, `orientation`, `rotation0`, `rotation1`,
     `rotation2`, `rotation3`;
   - the matching row in
     [specs/world-treasures/batch_01.csv](../../specs/world-treasures/batch_01.csv), which is the
     source of truth;
   - the `location` and `content_note` columns when the landmark changed.
10. Restart the local worldserver so the custom SQL re-applies, then walk to the chest and open it.

## Verification

- `.treasure list` prints 20 items for batch 1.
- The preview chest is solid, sits on the floor, and opens with a normal click.
- After the SQL apply, stand at the saved coordinates and run `.gobject near 20`; the chest entry
  and GUID appear in the list. `.gobject target 930001` also selects the nearest one.
- The item appears in the loot window and the unique rule refuses a second copy on the same
  character.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `There is no such command` | Account lacks `950152` at this login. | Grant `950101`/`950103`, then relog. |
| `There is no such command` after a relog | Role granted but the permission row or link is missing. | Check `rbac_permissions` and `rbac_linked_permissions` for `950152`; re-apply `gm_rbac_presets.sql`. |
| Preview spawns nothing | Missing gameobject template for the chest entry. | `.gobject target 930001`; confirm `world_treasures_batch_01.sql` applied. |
| `save` says to use the open world | You are in an instance, battleground, or arena. | Move to the open-world location. |
| Chest opens but the item cannot be taken | Character already owns it (`maxcount = 1`) or the bag is full. | The row is still shown; the client refuses the take. Check bags, bank, equipped. |
| Chest cannot be clicked at all | Old build without the unlocked-chest fix, or chest inside geometry. | Rebuild/restart; move the chest. |
| Export lines scroll out of the chat frame | Chat frame keeps a limited history. | Enable `/chatlog`, run the export, then log out and read `Logs/WoWChatLog.txt`. |

## Batch 1 placement status

The owner's 2026-11-23 pass found nine wrong positions. All nine were re-saved in game and applied on
2026-11-24; in-game re-verification is pending.

| Item | Name | Zone | Chest | Spawn | Status |
|---|---|---|---|---|---|
| 901001 | Goldshire Ledger | Elwynn Forest | 930001 | 5714501 | re-placed 2026-11-24; re-check pending |
| 901002 | Sentinel Hill Signal Lantern | Westfall | 930002 | 5714502 | pass |
| 901003 | Auberdine Tidecaller's Charm | Darkshore | 930003 | 5714503 | re-placed 2026-11-24; re-check pending |
| 901004 | Astranaar Moonguard Sigil | Ashenvale | 930004 | 5714504 | pass |
| 901005 | Booty Bay Smuggler's Coil | Stranglethorn Vale | 930005 | 5714505 | pass |
| 901006 | Gadgetzan Sandstorm Goggles | Tanaris | 930006 | 5714506 | re-placed 2026-11-24; re-check pending |
| 901007 | Marshal's Refuge Field Compass | Un'Goro Crater | 930007 | 5714507 | re-placed 2026-11-24; re-check pending |
| 901008 | Everlook Frostweave Blanket | Winterspring | 930008 | 5714508 | pass |
| 901009 | Light's Hope Prayer Beads | Eastern Plaguelands | 930009 | 5714509 | pass |
| 901010 | Brill Gravedigger's Spade | Undercity | 930010 | 5714510 | re-placed 2026-11-24; re-check pending |
| 901011 | Shimmering Flats Salt Goggles | Thousand Needles | 930011 | 5714511 | re-placed 2026-11-24; re-check pending |
| 901012 | Feathermoon Sentinel's Longbow | Feralas | 930012 | 5714512 | pass |
| 901013 | Honor Hold Bulwark Fragment | Hellfire Peninsula | 930013 | 5714513 | pass |
| 901014 | Cenarion Refuge Sporeling Charter | Zangarmarsh | 930014 | 5714514 | re-placed 2026-11-24; re-check pending |
| 901015 | Garadar Ancestor's Totem | Nagrand | 930015 | 5714515 | pass |
| 901016 | Area 52 Telemetric Rod | Netherstorm | 930016 | 5714516 | pass |
| 901017 | Valiance Keep Winter Cloak | Borean Tundra | 930017 | 5714517 | re-placed 2026-11-24; re-check pending |
| 901018 | Amberpine Trapper's Knife | Grizzly Hills | 930018 | 5714518 | re-placed 2026-11-24; re-check pending |
| 901019 | K3 Surveyor's Sextant | The Storm Peaks | 930019 | 5714519 | pass |
| 901020 | Crusader's Oathband | Icecrown | 930020 | 5714520 | pass |

All 20 crates failed to open on the first pass for a separate reason: unlocked chests were missing
the core direct-use branch, and `LOOT_CORPSE` is refused for spawned-by-default objects with a
respawn timer. The branch now uses `LOOT_SKINNING`, the same call the lockpicking path uses. Both the
opening bug and the nine positions are fixed; the owner's re-check is the remaining step.

## Capturing the export

`.treasure export` prints one `UPDATE` line per saved item. Nine lines do not fit in the chat frame,
and the server console does not receive player chat, so use the client chat log:

```
/chatlog
.treasure export
/chatlog
```

`/chatlog` toggles logging. The file is:

```text
~/Games/wotlk-clean/Logs/WoWChatLog.txt
```

The client buffers the file and writes it on logout or exit. **Log out to the login screen or close
the client** before reading it; until then the file is empty (0 bytes).

The export lives in server memory only. Do not restart the worldserver between `save` and reading the
log, or the saved positions are lost and must be captured again.

Alternative when the log cannot be used: screenshot the chat frame in two batches. The lines are
plain text and can be transcribed.

## Escalation

A crash, a missing chest after the SQL apply, or an item that cannot be looted by anyone is a bug
report, not a placement issue. Follow [bug-reports.md](../operation/bug-reports.md).

## References

- [ADR-031](../../decisions/ADR-031-world-treasures.md)
- [specs/world-treasures.md](../../specs/world-treasures.md)
- [modules/mod-treasure-placer/README.md](../../modules/mod-treasure-placer/README.md)
- [command-handbook.md](command-handbook.md)
