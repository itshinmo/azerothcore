# Client patches

Project client artifacts for the supported 3.3.5a client. Contract:
[specs/client-patch.md](../../specs/client-patch.md). Decisions:
[ADR-027](../../decisions/ADR-027-client-patch-pipeline.md).

## Ledger

| Patch | File | Contents | SHA256 | DBC files |
|-------|------|----------|--------|-----------|
| [item-data](item-data/README.md) | `item-data/dist/patch-X.MPQ` | `DBFilesClient\Item.dbc` with custom item rows; `dist/Item.dbc` for the server | `9ddd80c9fda95647c393a00fb2c0d2db706185b59c05364ce00d3899e95c1d50` | 1 |
| [map-pins](map-pins/README.md) | `map-pins/dist/patch-Z.MPQ` | `WorldMapPins` addon (7 world bosses, 10 Warpweavers, 15 Call Boards; data generated from tracked SQL and client DBC) + FrameXML canary + `Cooldown.lua` nil guard | `4c630fda4d373e91b58bcbdae0534dc444677026c103dab02e7ea3a31f2dbbeb` | 0 |
| [race-class-combos](race-class-combos/README.md) (proposal) | `race-class-combos/dist/patch-V.MPQ` | whole-file `CharBaseInfo.dbc` 62 -> 67 rows and `CharStartOutfit.dbc` 126 -> 134 rows for the proposed race/class pairs; not installed until approved | `50e4477b93678272ad35089bfbbd6c8fa7f884c98d1d3171491b29da49d4731c` | 2 |
| [white-boss-models](white-boss-models/README.md) | `white-boss-models/dist/patch-Y.MPQ` | stock goblin male model/skins/anims over the Ascension HD conversion | `b236c1c35d2714a0e6423e87a934256fbace13168951d2c5144b0ca30016f524` | 0 |

Project archive family on the English client: `patch-X` item data (only `Item.dbc` carrier),
`patch-Y` white models, `patch-Z` map/UI, and the proposed `patch-V` character-creation DBCs. All
load after Reforged `patch-U`; V < X < Y < Z.

## Rules

- Project archive family `Data/patch-<letter>.MPQ` on the English client, split by data domain.
  Vendor patches are never modified. Only X carries `Item.dbc`; V carries only the creation DBCs; a
  second carrier of either file is a build error.
- Whole-file replacement only. Resolve the source with `client_patch.py which` and rebuild after a
  bundle update.
- No exe or DLL content in an MPQ. No partial DBC. No vendor asset without a license, source, and hash.
- One artifact lives outside the MPQ family: the `DivxDecoder.dll` proxy proposed by
  [ADR-036](../../decisions/ADR-036-client-dll-patches.md). It is built from tracked source under
  `tools/client-dll/white-model-hook/`, is not part of any project archive, and its hash belongs in
  this ledger once the ADR is accepted and the artifact ships.
- Client artifacts are binary: `*.MPQ`, `*.mpq`, `*.dbc`, `*.DBC`, `*.blp`, `*.m2`, `*.skin`,
  `*.anim` are marked binary in `.gitattributes`. Verify `git hash-object --path=<path> <file>`
  equals `--no-filters` before committing an archive or DBC.
- Item.dbc rows mirror the server `item_template` row: class, subclass, material, display, inventory,
  sheathe. A display ID must exist in ItemDisplayInfo.dbc.
- Every patch has its build inputs, `build.py`, `dist/patch-<letter>.MPQ`, `manifest.json`, and a
  README with source hashes, install, test, and rollback steps.
- The owner installs and tests; agents do not write to the live client.

## Adding a patch

Create `data/client-patches/<feature>/` with its own README, build script, source, and manifest.
`build.py` must regenerate any derived data, pack MPQ v1 with listfile/attributes/zlib, verify every
entry, and write the manifest. Add the row above in the same change.
