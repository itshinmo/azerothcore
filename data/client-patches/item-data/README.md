# Item data (`patch-X.MPQ`)

Client-side `Item.dbc` rows for custom item IDs. Without a row the client shows the red question
mark in the bag even when the server has the item. This patch supplies the 8 fields the client needs:
ID, Class, SubClass, SoundOverrideSubclass, Material, DisplayInfoID, InventoryType, SheatheType.

Pipeline: [ADR-027](../../../decisions/ADR-027-client-patch-pipeline.md). The map/UI sibling is
[ADR-037](../../../decisions/ADR-037-world-map-pins.md). Contract:
[specs/client-patch.md](../../../specs/client-patch.md).

## Contents

| Entry | Value |
|-------|-------|
| Archive | `dist/patch-X.MPQ` |
| File | only `DBFilesClient\Item.dbc` |
| DBC rows | 8 fields, 32 bytes a row |
| Rows | 46,096 -> 46,116 |
| Added IDs | 901001-901020 (20 world-treasure items) |
| Archive SHA256 | `9ddd80c9fda95647c393a00fb2c0d2db706185b59c05364ce00d3899e95c1d50` |
| Archive size | 320,268 bytes |
| Item.dbc SHA256 | `ab6b3f61e901babd4e14a2c87aaffeab8e34158ee8ab033a074d9b4360218f13` |
| Server copy | `dist/Item.dbc` (same bytes as the MPQ entry) |
| Server input SHA256 | `d455bc30b59bc368b2a972a913864dd092d50695140b9513582100dc56ed777d` (local DataDir/dbc/Item.dbc at build time) |
| Source archive | `Data/enUS/patch-enUS-3.MPQ` |
| Source SHA256 | `d455bc30b59bc368b2a972a913864dd092d50695140b9513582100dc56ed777d` |
| `items.json` SHA256 | `9bb0ca8c8f1908fb810f33d6a0aff44a2d0a284022e70f420971cf01f57c30a6` |

The source is the highest-priority vendor Item.dbc below `patch-X`. The build rejects a source that
is already a project patch and rejects Item.dbc carried by `patch-Y` or `patch-Z`.

License: the packed files are the stock 3.3.5a client assets from the owner's own licensed install.
The custom rows are project data, not third-party assets.

## Rows

`items.json` is generated and validated from the frozen world-treasure sources under `source/`
(`batch_01.csv`, the `item_template` SQL, and the server `item_dbc` SQL mirror). It mirrors the server
`item_template` row:

| ID | Name | Class | Sub | Sound | Material | Display | Inv | Sheathe |
|----|------|-------|-----|-------|----------|---------|-----|---------|
| 901001 | Goldshire Ledger | 4 | 0 | -1 | 7 | 54808 | 23 | 0 |
| 901002 | Sentinel Hill Signal Lantern | 4 | 0 | -1 | 7 | 36575 | 23 | 0 |
| 901003 | Auberdine Tidecaller's Charm | 4 | 0 | -1 | 4 | 9657 | 2 | 0 |
| 901004 | Astranaar Moonguard Sigil | 4 | 0 | -1 | 1 | 9845 | 11 | 0 |
| 901005 | Booty Bay Smuggler's Coil | 4 | 2 | -1 | 8 | 28802 | 6 | 0 |
| 901006 | Gadgetzan Sandstorm Goggles | 4 | 1 | -1 | 7 | 19563 | 1 | 0 |
| 901007 | Marshal's Refuge Field Compass | 4 | 0 | -1 | 3 | 6562 | 12 | 0 |
| 901008 | Everlook Frostweave Blanket | 4 | 1 | -1 | 7 | 23136 | 16 | 0 |
| 901009 | Light's Hope Prayer Beads | 4 | 0 | -1 | 4 | 32008 | 2 | 0 |
| 901010 | Brill Gravedigger's Spade | 2 | 5 | -1 | 2 | 8585 | 17 | 1 |
| 901011 | Shimmering Flats Salt Goggles | 4 | 2 | -1 | 8 | 18322 | 1 | 0 |
| 901012 | Feathermoon Sentinel's Longbow | 2 | 2 | -1 | 2 | 28543 | 15 | 0 |
| 901013 | Honor Hold Bulwark Fragment | 4 | 6 | -1 | 1 | 40781 | 14 | 0 |
| 901014 | Cenarion Refuge Sporeling Charter | 4 | 0 | -1 | 7 | 44544 | 23 | 0 |
| 901015 | Garadar Ancestor's Totem | 4 | 0 | -1 | 3 | 37552 | 12 | 0 |
| 901016 | Area 52 Telemetric Rod | 2 | 19 | -1 | 2 | 43449 | 26 | 0 |
| 901017 | Valiance Keep Winter Cloak | 4 | 1 | -1 | 7 | 50050 | 16 | 0 |
| 901018 | Amberpine Trapper's Knife | 2 | 15 | -1 | 1 | 52445 | 13 | 3 |
| 901019 | K3 Surveyor's Sextant | 4 | 0 | -1 | 3 | 34188 | 12 | 0 |
| 901020 | Crusader's Oathband | 4 | 0 | -1 | 1 | 35313 | 11 | 0 |

Source data: frozen copies of the world-treasure batch CSV and SQL in `source/`; the server
`item_dbc` SQL is the mirror. `items.json` is generated with
`python3 data/client-patches/item-data/generate_items.py --write`; `--check` fails on any
class/subclass/display/inventory/sheathe/name mismatch between `items.json`, `item_template`, the
CSV, and the server `item_dbc` rows. The SQL `item_template` row is the gameplay source; `items.json`
copies only the fields Item.dbc needs. Every display ID was checked against the client's read-only
`ItemDisplayInfo.dbc`; a missing display fails the build unless the offline fixture path uses
`--no-display-check`, because a missing display is the red question mark. The manifest records
`"display_check": true`.

## Load order

`patch-X`, `patch-Y`, and `patch-Z` all load after Reforged `patch-U`. Alphabetic order is X < Y < Z,
so `patch-Z` remains the highest-priority map/UI archive, while `patch-X` wins Item.dbc because no
other project archive carries it. Only X carries a DBC; Y is reserved for white models and Z is the
map/UI layer. A second Item.dbc carrier is a build error.

There is no Lua canary in this archive. Verify with `which` and in-game:

```bash
python3 tools/client-patch/client_patch.py which \
  ~/Games/wotlk-clean/Data 'DBFilesClient\Item.dbc'
```

The winner must be `Data/patch-X.MPQ` after install.

The server also loads `DataDir/dbc/Item.dbc` through `sItemStore`. Publish the same bytes to the
server, or apply the same rows through the `item_dbc` table; choose one path and do not half-apply.
The `item_dbc` table rows are **separate** from a full server Item.dbc replacement. If the server
DBC has rows the client union lacks (for example the transmog preview `2050641`), the build with
`--server-dbc` fails; merge those rows into `items.json` first or leave the server file in place and
use `item_dbc` rows only.

```bash
# server owner, after a backup and before a restart
cp data/client-patches/item-data/dist/Item.dbc <server>/DataDir/dbc/Item.dbc
```

Full server-DBC replacement check:

```bash
python3 data/client-patches/item-data/build.py \
  --server-dbc <server>/DataDir/dbc/Item.dbc
```

The manifest then records the server input hash and rows. Server-only IDs or same-ID row conflicts
abort the build; they are never silently dropped.

The client MPQ and the server DBC share `Item.dbc` SHA256 `ab6b3f61...`. A client-only install
fixes the bag icon for a server item, but the server's `sItemStore` still lacks the custom rows; keep
both sides on the same source.

Before replacing the server file, compare it with the client source. Any server-only custom row (for
example `2050641` from the owner's earlier test) must be added to `items.json` and rebuilt; a blind
overwrite would lose it. Build source and server source must be the same vendor DBC plus the union of
custom rows.

## Build

```bash
export STORMLIB=/opt/homebrew/lib/libstorm.dylib   # only when needed
python3 data/client-patches/item-data/generate_items.py --check
python3 data/client-patches/item-data/build.py
python3 data/client-patches/item-data/build.py --check
python3 data/client-patches/item-data/build.py --server-dbc <server>/DataDir/dbc/Item.dbc
python3 tools/client-patch/item_dbc.py inspect \
  --archive data/client-patches/item-data/dist/patch-X.MPQ --ids 901001-901020
```

The build validates `items.json` against the frozen sources, resolves the vendor Item.dbc, upserts
every row, sorts by ID, validates the 8-field/32-byte shape, checks display IDs against
ItemDisplayInfo.dbc, packs only Item.dbc, writes the matching `dist/Item.dbc` for the server, and
writes `manifest.json`. With `--server-dbc`, it also records the server hash and aborts on server-only
IDs or row conflicts. Unchanged inputs rebuild byte-identically (fixed entry times).

The editor is also usable without an MPQ:

```bash
python3 tools/client-patch/item_dbc.py inspect --dbc Item.dbc --ids 901001-901020
python3 tools/client-patch/item_dbc.py edit --dbc Item.dbc --items items.json --out Item.dbc.new
```

## Install

Client closed.

```bash
cp data/client-patches/item-data/dist/patch-X.MPQ ~/Games/wotlk-clean/Data/patch-X.MPQ
```

The map/UI patch is independent; copy `patch-Z.MPQ` as well when testing both.

## In-client test steps

1. The client patch only draws the row the server already has. The server must have a matching
   `item_template` row. For the first rows, apply the world-treasures SQL to a test world database or
   use a realm where it is already applied. Do not edit the `feat-world-treasures` worktree.
2. Start the client and log in. There is no Item.dbc canary; check `which` after install.
3. As a GM, grant a row: `.additem 901001` (Goldshire Ledger). Open the bag.
4. The item shows its normal icon and tooltip. A red question mark means the Item.dbc row or its
   DisplayInfoID is missing, or `patch-X` did not load.
5. Repeat with representative fields: `901010` (two-hand, sheathe 1), `901012` (bow, inventory 15),
   `901018` (dagger, sheathe 3), `901020` (ring, inventory 11). If the server has all rows, test a
   few; otherwise use whichever custom IDs the realm has.
6. Delete `patch-X.MPQ`, restart, and grant the same item again. The red question mark should return;
   that proves the patch was the source. Reinstall for normal play.

## Rollback

```bash
rm ~/Games/wotlk-clean/Data/patch-X.MPQ
```

No server data changes, no other DBC, no cache purge. Custom item IDs without a row show the red
question mark again.

## What is left for Mythic+ item rows

The Mythic+ work is not in this patch. Its ranges are proposed in
`feat-mythic-plus/decisions/ADR-034-mythic-plus-old-content.md`:

- `1100000-1899999` — obtainable generated scaled copies;
- `1900000-1999999` — non-obtainable/QA copies.

No Mythic+ `item_template` rows exist yet. When they do, do not hand-write them: generate the
Item.dbc rows from the same `item_template` source (class, subclass, material, display, inventory,
sheathe), append them to a generated items JSON, and rebuild `patch-X`. Every custom display must
already exist in ItemDisplayInfo.dbc or the item will still show the red question mark. The range is
large (hundreds of thousands of possible IDs), so the generator — not a manual list — owns it.
