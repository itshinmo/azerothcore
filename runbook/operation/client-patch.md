# Client patch

Build, verify, install, and roll back the project client-patch family (`patch-X/Y/Z.MPQ`) for the
supported 3.3.5a English client. Contract: [specs/client-patch.md](../../specs/client-patch.md).
Decisions:
[ADR-027](../../decisions/ADR-027-client-patch-pipeline.md),
[ADR-037](../../decisions/ADR-037-world-map-pins.md).

## When to use

- A feature needs client-side Lua/XML, a client DBC, or a map layer that server data cannot draw.
- A built patch must be installed or removed from a client copy.
- A patch does not load and the load order must be proven.

Do not use this for server content, SQL, RBAC, or audit. Those stay server-side.

## Prerequisites

- The verified client bundle ([client-bundle.md](client-bundle.md)). The English chain is assumed.
- StormLib: `brew install stormlib`; export `STORMLIB=/opt/homebrew/lib/libstorm.dylib` when the
  default search misses it.
- Python 3.10+ and `luajit` for the Lua syntax gate (`brew install luajit`).
- The client is closed before installing or removing a patch.

Check:

```bash
python3 -c 'import sys; sys.path.insert(0,"tools/client-patch"); import mpq; print(mpq.stormlib_path())'
python3 tools/client-patch/client_patch.py inspect data/client-patches/map-pins/dist/patch-Z.MPQ
python3 tools/client-patch/client_patch.py inspect data/client-patches/item-data/dist/patch-X.MPQ
```

## Inspect the client before building

```bash
DATA=~/Games/wotlk-clean/Data
python3 tools/client-patch/client_patch.py which "$DATA" 'Interface\FrameXML\WorldMapFrame.lua'
python3 tools/client-patch/client_patch.py which "$DATA" 'DBFilesClient\WorldMapArea.dbc'
python3 tools/client-patch/client_patch.py which "$DATA" 'DBFilesClient\Spell.dbc'
```

`which` prints the winner and every lower archive containing the path. The winner is the file the
client reads and the whole-file source for a replacement. If the path exists in a project archive
(`patch-X`, `patch-Y`, or `patch-Z`), that archive is already installed; remove it before taking a
source from the same client.

## Build a feature patch

1. Create `data/client-patches/<feature>/src/` with the files to pack. Use client paths under
   `Interface/` and `DBFilesClient/`.
2. Resolve the source of every overridden file with `which`. Extract it whole:

   ```bash
   python3 tools/client-patch/client_patch.py extract \
     "$DATA/enUS/patch-enUS-3.MPQ" /tmp/client-patch-src \
     'Interface\FrameXML\WorldMapFrame.lua'
   ```

3. Edit the extracted file. Append a Lua block or change the whole file; do not ship a partial DBC.
4. Pack:

   ```bash
   python3 tools/client-patch/client_patch.py pack \
     data/client-patches/<feature>/dist/patch-X.MPQ \
     data/client-patches/<feature>/src
   ```

5. Write and verify the manifest:

   ```bash
   python3 tools/client-patch/client_patch.py manifest \
     data/client-patches/<feature>/dist/patch-X.MPQ \
     --out data/client-patches/<feature>/manifest.json
   python3 tools/client-patch/client_patch.py verify \
     data/client-patches/<feature>/dist/patch-X.MPQ \
     --manifest data/client-patches/<feature>/manifest.json --verbose
   ```

6. Record the source archive, source SHA256, output SHA256, install steps, test steps, and rollback
   in the feature README. Add the patch to `data/client-patches/README.md`.

The map-pins feature has a build script that does the source resolution, canary append, pack, and
manifest in one step:

```bash
python3 data/client-patches/map-pins/build.py
python3 data/client-patches/map-pins/build.py --check
```

The item-data feature builds `patch-X.MPQ` with only `DBFilesClient\Item.dbc`:

```bash
python3 data/client-patches/item-data/generate_items.py --check
python3 data/client-patches/item-data/build.py
python3 data/client-patches/item-data/build.py --check
python3 data/client-patches/item-data/build.py \
  --server-dbc <server>/DataDir/dbc/Item.dbc
python3 tools/client-patch/item_dbc.py inspect \
  --archive data/client-patches/item-data/dist/patch-X.MPQ --ids 901001-901020
```

The build validates `items.json` against the frozen batch CSV, item_template SQL and item_dbc mirror,
resolves the highest-priority vendor Item.dbc below `patch-X`, upserts every row, sorts by ID,
validates 8 fields and 32-byte rows, checks each display ID against ItemDisplayInfo.dbc, packs only
Item.dbc, verifies it, and writes the manifest. If Item.dbc is already carried by `patch-Y` or
`patch-Z`, stop: X cannot win and a whole-file DBC conflict exists. A missing ItemDisplayInfo.dbc
fails the build unless `--no-display-check` is used for an offline fixture.

With `--server-dbc`, the build unions/diffs the server DataDir Item.dbc: server-only IDs and same-ID
row conflicts abort. The `item_dbc` table rows are a separate deployment path; do not mix a full
server Item.dbc replacement with a different half-applied table set.

`--check` compares the built archive and every entry against the committed manifest. It fails on a
stale patch.

## Install and test

The owner installs; agents do not write to the live client.

```bash
# client closed
cp data/client-patches/map-pins/dist/patch-Z.MPQ ~/Games/wotlk-clean/Data/patch-Z.MPQ
cp data/client-patches/item-data/dist/patch-X.MPQ ~/Games/wotlk-clean/Data/patch-X.MPQ
```

Then, with the client started:

1. The login chat shows the canary line from `Interface\FrameXML\WorldMapFrame.lua`.
2. The login chat shows the `WorldMapPins` load line with the pin count.
3. Trigger a quest-item cooldown or the Call of Water path; no `Cooldown.lua` error.
4. Open the world map in Stormwind. The Warpweaver and Call Board pins sit on their exact spots.
5. Hover each pin: the tooltip shows name, kind and place. Click a pin: the stock map ping fires.
6. Zone maps draw only their own pins: Duskwood shows Taerar, Westfall shows none.
7. Dalaran city micro-map: Warpweaver and Call Board on their spots.
8. Continent maps draw only that continent: Eastern Kingdoms 11, Kalimdor 14, Outland 5,
   Northrend 2.
9. `/reload`, reopen the map; no Lua error dialog and no `Interface\AddOns\WorldMapPins` error.
10. Close the map; pins are hidden, no map work continues.
11. Item data: a server `item_template` row is required. Grant a custom item, for example
   `.additem 901001`, and inspect the bag icon and tooltip. The icon must render; a red question
   mark means the Item.dbc row or its DisplayInfoID is missing.
12. Server: restart with matching data. Copy `data/client-patches/item-data/dist/Item.dbc` to
    `<server>/DataDir/dbc/Item.dbc` (owner only; back up first), or apply the same rows through the
    `item_dbc` table. Do not half-apply. The server loads Item.dbc through `sItemStore`. Compare the
   server file first: any server-only custom rows (for example `2050641`) must be in `items.json`
   and rebuilt, or the replacement loses them.

The pin and tooltip logic has an offline test:

```bash
luajit data/client-patches/map-pins/tests/test_addon.lua
```

Pin data and sources are in [data/client-patches/map-pins/README.md](../../data/client-patches/map-pins/README.md).

Prove load order after install:

```bash
python3 tools/client-patch/client_patch.py which "$DATA" 'Interface\FrameXML\WorldMapFrame.lua'
```

The winners must be `Data/patch-Z.MPQ` for the map path and `Data/patch-X.MPQ` for Item.dbc:

```bash
python3 tools/client-patch/client_patch.py which "$DATA" 'Interface\FrameXML\WorldMapFrame.lua'
python3 tools/client-patch/client_patch.py which "$DATA" 'DBFilesClient\Item.dbc'
```

## Rollback

Client closed, then:

```bash
rm ~/Games/wotlk-clean/Data/patch-Z.MPQ
rm ~/Games/wotlk-clean/Data/patch-X.MPQ
```

The map patch needs no server rollback. The client returns to the previous behavior on the next
start; custom item IDs without Item.dbc rows show the red question mark again. A client `Cache` purge
is not required. If the server `DataDir/dbc/Item.dbc` was replaced, restore it from the pre-change
backup and restart; if rows went through `item_dbc`, remove those rows with the same care as any
DB write.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `StormLib error 0` on open | StormLib missing or wrong path | `brew install stormlib`; set `STORMLIB` to the dylib. |
| `which` skips an archive | Archive is encrypted or corrupt | Expected for some vendor patches; use the source it reports. |
| Canary absent in game | `patch-Z` did not load; a lower archive won | Re-run `which`; confirm the client is English; check the file name case. |
| Addon load line absent | MPQ addon did not load or is disabled | Check the addon list; re-verify the TOC and the `Interface\AddOns` path. |
| Markers on the wrong spot | Spawn moved or map convention mismatch | Edit the matching row in `data/client-patches/map-pins/src/WorldMapPins/WorldMapPins.lua`; compare a known NPC in game; rebuild. |
| Dalaran markers wrong | WorldMapArea has zero bounds for Dalaran | Recompute the pair from `DungeonMap.dbc` row 27 (map 571); rebuild. |
| Silvermoon or Exodar markers in the ocean | Continent fraction projected without the map-530 `WorldMapTransforms` offset | Add `(-2400, +2400)` for Eastern Kingdoms or `(+10133.333, +17600)` for Kalimdor before projecting; zone fractions stay raw. |
| Lua error at login | FrameXML source changed under a new bundle | Rebuild from the new highest-priority source; do not reuse the old patch. |
| `verify` fails after a rebuild | Expected: a rebuild changes the archive hash | Regenerate the manifest and commit both. |
| Custom item shows a red `?` | Item.dbc row missing, DisplayInfoID missing, or `patch-X` not loaded | Run `item_dbc.py inspect --archive ... --ids <id>`; confirm `which Item.dbc` is `patch-X`; check ItemDisplayInfo.dbc. |
| `Item.dbc` header rejected | Not 8 fields / 32-byte rows | Use the client's 3.3.5a Item.dbc, not a Cataclysm or later table. |
| Item.dbc conflict | `patch-Y` or `patch-Z` also carries Item.dbc | Remove the other carrier; X must be the only one. |
| Pin tooltip absent | Wrong parent, or the pin is under the client quest POI layer | Parent to `WorldMapFrame` at `GetFrameLevel() + 7` with the frame's strata, `EnableMouse(true)`, and hide via `WorldMapTooltip` with `WorldMapPOIFrame.allowBlobTooltip = false`. `/wmp` prints the frame under the cursor. |

## References

- [specs/client-patch.md](../../specs/client-patch.md)
- [ADR-027](../../decisions/ADR-027-client-patch-pipeline.md)
- [ADR-037](../../decisions/ADR-037-world-map-pins.md)
- [client-bundle.md](client-bundle.md)
- `tools/client-patch/README.md`
