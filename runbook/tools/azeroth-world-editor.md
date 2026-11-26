# Azeroth World Editor

## When to use

You need to see a spawn in 3D, move an existing NPC or gameobject to a better spot, check a patrol, or
read a vendor or trainer before drafting SQL for it. This runbook covers the app as installed on the
owner's Mac, the project's connection values, and the one safe workflow: move existing rows, export a
patch, review it.

## What it is

Azeroth World Editor (AWE) is a desktop world editor for an AzerothCore world database. It draws the
game world from a local client, lets you place, move, group and script NPCs and objects in 3D, and
writes the result as a SQL patch.

| Property | Value |
|----------|-------|
| App | `/Applications/Azeroth World Editor.app` |
| Version | `0.10.0`, arm64 (Apple silicon), about 370 MB |
| Runtime | Electron desktop app; not a server, no browser tab |
| Licence | GPL-3.0-or-later |
| Author | DMCK96 |
| Source | https://github.com/DMCK96/azeroth-world-editor |
| Docs | https://dmck96.github.io/azeroth-world-editor/ |

It reads the world database. It never writes to the database you connect with: edits stay in an
in-app project and leave as SQL, or go to a separate dev database you configure yourself.

## Install and the unsigned-app gate

The installer is not code-signed. macOS refuses the first launch.

1. Drag the app into `/Applications`.
2. Open it. macOS refuses and says it cannot check the app for malicious software. Choose **Done**,
   not **Move to Trash**.
3. Open **System Settings > Privacy & Security**, scroll to **Security**, choose **Open Anyway**
   beside the message about Azeroth World Editor, and confirm with the password.
4. Open the app again and choose **Open Anyway**. Later launches open normally.

Alternative, when the app is already in `/Applications`:

```bash
xattr -cr "/Applications/Azeroth World Editor.app"
```

On macOS 14 and earlier, right-click the app and choose **Open**, then **Open** again.

## Connection fields

The login screen asks for the world database on the left and the optional folders on the right. Use
these values for the local realm:

| Field | Value | Notes |
|-------|-------|-------|
| Host | `127.0.0.1` | Local MySQL only |
| Port | `3306` | Default MySQL port |
| User | `acore` | The existing application account |
| Password | value from `WorldDatabaseInfo` | In `env/dist/etc/worldserver.conf`, main checkout; never committed |
| Database | `acore_world` | Never point this at a characters or auth database |
| Server data folder | `/Users/gasman/wow/Data` | Holds `dbc/`, with `maps/` and `mmaps/` beside it |
| Game client folder | `/Users/gasman/Games/wotlk-clean` | Holds `Wow.exe` |
| Export folder | `/Users/gasman/wow/azerothcore/data/sql/custom/db_world` | Tracked project SQL |
| Dev database | leave empty | See [Export vs Apply to dev](#export-vs-apply-to-dev) |

The top bar confirms what opened: **Connected: acore_world**, plus **Server data** and **Game
client** when those folders read correctly.

The password is stored encrypted by the app. After one save the field reads **Saved — leave blank to
keep**.

**Security note.** The `acore` account can write to the world database. The "never writes" guarantee
is the app's behaviour, not a database grant. A read-only account would make the guarantee
enforceable; the owner chose `acore` for this install instead. Do not use `root`, and do not reuse
these values on production: production stays human-only and read-only for tools.

## What each folder unlocks

| Folder | Unlocks | Breaks without it |
|--------|---------|-------------------|
| Server data | XP per tier, search by name, floors, snapping | IDs typed by hand; no floor, spawns can land wrong |
| Game client | The **World** pane in 3D | The pane reports it missing; only editors work |
| Export folder | Where patches are written | Patches go to `~/Documents/Azeroth World Editor/sql` |
| Dev database | **Apply to dev DB** | The button stays disabled; export is the only path |

Ground snapping needs `maps/` and `mmaps/` beside `dbc/`, so the server data folder must be the whole
`Data` tree, not a copy of `dbc/` alone.

The export folder points into the main checkout (`/Users/gasman/wow/azerothcore`). When you work in a
worktree, copy the coordinates from the export into that worktree's copy of the tracked file, and keep
the main checkout untouched.

## First-run checklist

1. Confirm MySQL is running: `make status`.
2. Open the app and fill in the fields above. Choose **Connect**.
3. Check the top bar shows **Connected: acore_world**, **Server data** and **Game client**.
4. In **World**, use **Find…** and search `910012` (Warpweaver). It lists every spawn, nearest
   first. Choose **Go** on the nearest one. The camera must fly there and the NPC must be visible.
5. Switch to **Select** and click the NPC. Its card must show entry `910012` and a spawn GUID in
   `5400001–5400010`.
6. Press **Play** for a moment, then **Reset**. Movement previews must return every NPC to its spawn.
7. Do nothing else yet. The project is empty, and no database row has changed.

## The World pane

The pane opens where you left it, on the map of the last place.

### Camera

| Input | Action |
|-------|--------|
| Right-drag | Look around |
| Left-drag | Orbit round the point under the cursor (Camera mode) |
| Middle-drag | Pan |
| Wheel | Move forward and back |
| `W` `S` `A` `D` | Fly forward, back, strafe |
| `Q` `E` | Turn left and right |
| `Space` `X` | Rise and sink |
| `Shift` | Faster |
| `Alt+Left` | Go back to the previous camera place |

Keys work after the view has been clicked. **?** in the bottom right lists every control.

### Selecting

`Tab` switches between **Camera** and **Select**. In Select mode:

- left-drag draws a box; **Shift**-click adds, **Ctrl**-click removes;
- **G** moves, **R** rotates, with handles on the selection;
- **Delete** removes the selected spawns, or the picked route points when a route is shown;
- **Ctrl+Z** and **Ctrl+Y** undo and redo one whole move or turn.

### Ground snapping

A moved spawn drops onto the server's floor where you let go. Hold **Alt** while dragging to snap
NPCs, objects and path points onto the terrain or building floor under them. Without **Alt**, only
the yellow square follows the ground.

**O** turns on falloff, so nearby route points follow a move, less with distance; `[` and `]` change
the radius. Settings > Preferences sets the floor tolerance, 1 yard by default: how close the server's
floor must be to the snapped surface before it replaces it.

### The axis gizmo

The handles on a selection are coloured arrows: **red for X, green for Y, blue for Z**. Drag one arrow
to move along that axis only; drag a square handle to move in that pair of axes; drag the centre to
move freely. **R** replaces the arrows with rotation rings. The card beside the selection shows the
current position, so a value can be read before letting go.

## Move an existing NPC and export the patch

This is the working procedure for relocating the Adventure Quartermasters (`910020` Stormwind spawn
`5400011`, `910021` Orgrimmar spawn `5400012`) and the ten Warpweaver spawns (`910012`, GUIDs
`5400001–5400010`). They are the rows with crowd problems: bank steps, auction-house posts, doorways.

1. Back up first. The move is one `UPDATE` per spawn, but rollback needs the old coordinates:

   ```bash
   make backup
   ```

2. Open the app, connect, and confirm the three top-bar badges.
3. **Find…** the entry: `910020`, `910021`, or `910012`. The dialog lists every spawn, nearest first.
   Choose **Go** on the one to move.
4. Click the NPC to select it. The card must show the expected entry and spawn GUID. If it shows a
   different GUID, stop: you are looking at a duplicated or stray spawn.
5. Read the card: X, Y, Z, map. Write the old values down, or rely on the backup from step 1.
6. Switch to **Select**, press **G**, and drag the NPC to the new spot. Hold **Alt** so it snaps to
   the floor. Keep it within a few yards of the original; a quartermaster or transmogrifier that
   moves across the district breaks every guide that points at it.
7. Press **R** and turn the NPC to face the approach, usually the same direction as the neighbouring
   auctioneer or bank.
8. Press **Play**, watch for a moment, then **Reset**. The NPC must stand where you put it, on the
   floor, not inside a crate, rail, or wall.
9. Open **Project changes** in the Layers card. The row must read **Spawns changed**, with the old and
   new position. **Revert** is available and must return the NPC to the old spot; use it once to prove
   the change is tracked, then move the NPC again.
10. Choose **Export project patch**. Two files land in the export folder:

    ```text
    rev_<yyyymmdd>_<nn>_<project>.sql
    rev_<yyyymmdd>_<nn>_<project>_revert.sql
    ```

11. Open the patch and check it. A move must be an `UPDATE` on `creature` or `gameobject` filtered by
    the existing `guid`. Any `INSERT`, any new `entry`, and any GUID outside the project blocks is a
    refusal: discard the patch, see [ID-range conflict](#id-range-conflict).
12. Treat the export as a scratch artifact, not the change. Copy the new coordinates into the tracked
    source file: `data/sql/custom/db_world/collections_npc_spawns.sql` for the Warpweavers and
    `data/sql/custom/db_world/objectives_engine.sql` for the quartermasters. Both are
    `DELETE` + `INSERT`, so replacing the tuple is the whole change.
13. Delete the exported `.sql` and `_revert.sql` from the export folder once the tuple is in place.
    The worldserver applies every new file in that folder in filename order, and `_revert.sql` sorts
    after its patch, so a leftover pair ends with the move undone. The old coordinates stay in
    `git diff` and in the backup, so nothing is lost.
14. Lint, then restart so the local worldserver applies the custom SQL (ADR-018). Do not restart
    while an unreviewed export is still in the folder: the restart applies it:

    ```bash
    python3 apps/codestyle/codestyle-sql.py
    make stop
    make start
    ```

15. Verify in game with [Verification and rollback](#verification-and-rollback).

The app writes the spawn's `wander_distance` and `MovementType` too when they change. A move alone
does not touch them, but check the patch: a quartermaster with a wander distance is a quartermaster
that walks away from its post.

A gameobject moves the same way: right-click it, **G** and **R**, then **Export project patch**. Its
patch updates `gameobject` instead of `creature`; the ID rule and the verification are unchanged,
except that `.gobject near` and `.go gameobject <spawnGuid>` replace the creature commands.

## The NPC editor

Open it from the right-click menu in the World: **Edit NPC…**. An existing NPC's title ends in
**(existing)**. The tabs used by this project:

- **Basics**: name, title, level, faction, visibility.
- **Look & gear**: borrow another creature's look and weapons, set scale.
- **Vendor**: what it sells. **Make this NPC a vendor** adds the first row. Each row has the item,
  **Max count** (0 is unlimited), **Restock** in seconds, and **Extended cost**. A shared vendor list
  shows read-only and offers **Give it its own copy**.
- **Trainer**: type, class, greeting, and each spell with cost, level, skill and prerequisites. Most
  class trainers share one trainer row, so a shared trainer is read-only until you give this NPC its
  own copy.
- **Gossip**: menu text and options, including service options.
- **Placement**: spawns, with **Place in world** and a field for the output of the in-game `.gps`
  command.

### Patrols

A selected NPC shows its route. Drag points to move them, **Shift**-click adds a point, **Delete**
removes the picked ones. Right-click a point and choose **Point settings…** to set wait time, walk or
run, facing, and actions: say a line, play an emote, hold a pose, cast a spell, play a sound, mount,
dismount, use an object. **Remove path** in the right-click menu takes the route away.

A route shared by several spawns asks before it changes for all of them. New or changed patrols load
after a server restart, not on `.reload`.

### Vendor and trainer tabs

Both are safe to open: opening an NPC writes nothing. The patch writes stock or spells only when you
change them, and the revert patch restores the original rows. Anything the app cannot represent is
read-only with a line saying why. Never use these tabs to add stock to a new NPC in this project;
that is content authoring and belongs in tracked SQL with a registered entry.

## Export vs Apply to dev

| Path | What it does | Use here |
|------|--------------|----------|
| Export patch / Export project patch | Writes `.sql` files to the export folder | Yes |
| Apply to dev DB | Writes straight into a configured dev database | No |

We only export, for three reasons. The patch is a file that gets reviewed, linted and committed, so
every row has an author and a diff. Apply-to-dev writes directly and leaves no tracked artifact.
There is no dev database to apply to: the test realm was removed and the launch realms do not exist
yet ([ADR-018](../../decisions/ADR-018-realm-strategy.md)). And a dev target on the same MySQL
instance is one settings mistake away from the real world database.

A patch can touch these tables, so a review reads them by name:

```text
creature, gameobject, creature_template, creature_template_model, creature_equip_template,
creature_addon, waypoint_data, smart_scripts, creature_text, conditions, gossip_menu,
gossip_menu_option, npc_text, npc_vendor, trainer, trainer_spell, creature_default_trainer,
page_text, creature_loot_template, gameobject_loot_template, quest_template,
quest_template_addon, quest_offer_reward, quest_request_items, creature_queststarter,
creature_questender, gameobject_queststarter, gameobject_questender, quest_poi, quest_poi_points
```

The move procedure above touches only `creature` and `gameobject`. Every other table in that list
means the patch is doing more than a move, and needs the content-author's review before it is kept.

## ID-range conflict

The app allocates IDs for new rows from `60000` upwards; its documentation says a new quest starts at
`60000`. This project reserves its content above `900000`:

| Kind | Reserved range |
|------|----------------|
| Items | `900000–909999` |
| Creatures | `910000–919999` |
| Quests | `920000–929999` |
| GameObjects | `930000–939999` |
| Spells | `940000–949999` |
| Misc (text, conditions, other) | `950000–959999` |
| Maps | `1000+` (client patch) |

See [id-registry.md](../database/id-registry.md).

The conflict is concrete, not theoretical:

- The app's allocation base is `60000`, below the lowest reserved project block (`900000`). Its
  counter walks up through the stock ID space, which upstream content also uses, and it knows
  nothing about this registry. An app-picked ID is therefore either below every reserved range, or
  an unregistered intrusion into one.
- `60000` is already occupied. The base world data has creature spawn GUID `60000` (entry `17132`) and
  gameobject spawn GUID `60000` (entry `187567`). The block `60000–60999` holds 1000 creature spawn
  GUIDs and 711 gameobject spawn GUIDs, so the app walks past taken keys before it finds a free one.
- The app refuses to export an ID it finds taken, which protects the database but does not make the
  chosen ID a project ID. A free key in the 60000s is still outside every reserved range.

**The rule that follows: use Azeroth World Editor to move existing rows, never to create content.**
Moving a spawn is an `UPDATE` on a row that already exists, and its GUID already belongs to the
project block. Creating an NPC, object, item, quest, trainer, vendor or loot row belongs to the
content-author, in tracked SQL, with an ID from the registry.

What to do when a patch contains a new row: discard it. Re-do the work as a move, or hand the new
content to the content-author with the coordinates and the intent.

## What it cannot do

| Limitation | Consequence |
|------------|-------------|
| Transports, zeppelin and boat routes | Vessels are drawn; routes are read-only, so a new route cannot be made here |
| Portal lists | `areatrigger_teleport` is not edited |
| PvP zone masks | Not edited; the app does not model the PvP zone flags |
| DBC files | No `Spell.dbc`, `Item.dbc` or `CharBaseInfo.dbc` edit; that is the client-patch pipeline |
| Client patches | No MPQ, model or map change; see [client-patch.md](../operation/client-patch.md) |
| Arbitrary SQL | It writes the tables it models, not free-form queries; a schema change is DBeaver or tracked SQL |

A feature that needs one of these is not an AWE job. Stop and route it to the client-patch pipeline or
the content-author.

## Verification and rollback

Run these as a GM on the local realm. Use the `admin` role (`950103`): `.npc delete` (`576`),
`.gobject near` (`394`) and `.go` (`377`) are not in the `content-tester` role. `content-tester` does
include `.npc near` (`594`), so a look-only check is available to it.

```text
.npc near 20                      # guid, entry, x, y, z, map of creatures within 20 yards
.gobject near 20                  # gameobject spawns within 20 yards
.go creature <spawnGuid>          # teleport to a creature spawn by GUID
.go gameobject <spawnGuid>        # teleport to a gameobject spawn by GUID
.npc delete                       # delete the selected spawn from the database
```

There is no `.go object` subcommand. The real one is `.go gameobject`, and it takes the spawn GUID,
not the template entry: `.go gameobject 60000`, not `.go gameobject 187567`. Variants:
`.go gameobject id <entry>` is the nearest spawn of a template, `.gobject target <entry>` selects it,
and `.lookup object <entry>` prints the template.

1. `.npc near 20` at the new spot. The spawn's GUID and entry must be the expected pair, the
   coordinates must match the patch, and the Z must sit on the floor rather than under it.
2. Walk to the NPC from the normal approach. It must be reachable, not behind a counter, and its
   gossip, vendor or trainer window must still open.
3. Check the neighbours: an NPC moved onto another spawn's spot causes overlap that the card view
   does not show. `.npc near 5` makes overlap obvious.
4. For a gameobject, `.gobject near 20` and `.go gameobject <spawnGuid>`.

Rollback, in order of preference:

1. Restore the tracked tuple: `git checkout -- data/sql/custom/db_world/<file>.sql`, then `make stop &&
   make start`. This works because the coordinates were folded into the tracked file, not left only in
   the export.
2. Restore the backup from step 1 of the move procedure
   ([backup-restore.md](../operation/backup-restore.md)). Use this when the tracked file has other,
   wanted changes that a checkout would also drop.
3. For a stray spawn created during testing, select it and use `.npc delete`. This deletes the row from
   the database; it is not a rollback for a tracked spawn.

The exported `_revert.sql` is not part of rollback: the procedure deletes it, because leaving it in the
apply folder makes the revert run after the patch.

A moved spawn, a new spawn and a changed patrol all load at server start. Restart before judging the
result; a `.reload` does not move a spawn.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| First launch refused as unverified | Unsigned app; Gatekeeper | Privacy & Security > Open Anyway, or `xattr -cr` |
| World empty, or wants a client | Client folder wrong or lacks `Wow.exe` | `/Users/gasman/Games/wotlk-clean` |
| "No game client folder" banner | Same as above; the World needs the client | Set the folder; editors still work |
| No floors, heights or snapping | Server data folder incomplete or unset | Server data: `/Users/gasman/wow/Data` |
| Spells and models are ID-only | Server data folder not loaded | Same field; check the **Server data** badge |
| Connection refused | MySQL down, wrong port, wrong interface | `make status`; check the host and port |
| `Access denied for user 'acore'` | Wrong password or host mismatch | Password from `worldserver.conf` |
| Permission denied on export | Export folder missing or unwritable | Use `data/sql/custom/db_world`; check it exists |
| Moved NPC still at the old spot | Spawns load at server start | `make stop && make start`, then re-check |
| New row in the patch | Content creation, not a move | Discard; see [ID-range conflict](#id-range-conflict) |

Run the commands from the repository root. The `acore` grant is created for `localhost`; a TCP login
can match a different host, which is the usual cause of the access-denied line above.

## Escalation

A patch that fails to apply, a spawn that disappears, or a position that will not survive a restart
is a bug, not a placement problem. Follow [bug-reports.md](../operation/bug-reports.md). A move that
needs a client asset, a map, or a DBC change is out of scope here; route it to the client-patch
pipeline.

## References

- https://github.com/DMCK96/azeroth-world-editor
- https://dmck96.github.io/azeroth-world-editor/
- [id-registry.md](../database/id-registry.md)
- [dbeaver.md](../database/dbeaver.md)
- [apply-sql-update.md](../operation/apply-sql-update.md)
- [backup-restore.md](../operation/backup-restore.md)
- [client-patch.md](../operation/client-patch.md)
- [treasure-placer.md](../gm/treasure-placer.md)
- [decisions/ADR-018-realm-strategy.md](../../decisions/ADR-018-realm-strategy.md)
