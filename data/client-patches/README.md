# Client patches

Project client artifacts for the supported 3.3.5a client. Contract:
[specs/client-patch.md](../../specs/client-patch.md). Decisions:
[ADR-027](../../decisions/ADR-027-client-patch-pipeline.md).

## Ledger

| Patch | File | Contents | SHA256 | DBC files |
|-------|------|----------|--------|-----------|
| [item-data](item-data/README.md) | `item-data/dist/patch-X.MPQ` | `DBFilesClient\Item.dbc` with custom item rows; `dist/Item.dbc` for the server | `9ddd80c9fda95647c393a00fb2c0d2db706185b59c05364ce00d3899e95c1d50` | 1 |
| [map-poi](map-poi/README.md) | `map-poi/dist/patch-Z.MPQ` | `ServerMapPOI` baked map layer (static + token-gated Outlaw protocol) + FrameXML canary | `1aaf23a4140a092bdad1fa0cfa8b270e8d369faef38cff85e7915c9b4b055d3f` | 0 |
| white-boss-models (`fix-journal-white-models` branch) | `white-boss-models/dist/patch-Y.MPQ` | stock goblin male model/skins/anims over the Ascension HD conversion | `b236c1c35d2714a0e6423e87a934256fbace13168951d2c5144b0ca30016f524` | 0 |

Project archive family on the English client: `patch-X` item data (only Item.dbc), `patch-Y` white
models (owned by `fix-journal-white-models`; manifest `data/client-patches/white-boss-models/manifest.json`
in that branch), `patch-Z` map/UI. All load after Reforged `patch-U`; X < Y < Z. This branch
cross-references Y and does not rebuild or overwrite it.

## Rules

- Project archive family `Data/patch-X/Y/Z.MPQ` on the English client, split by data domain. Vendor
  patches are never modified. Only X carries Item.dbc; a second carrier is a build error.
- Whole-file replacement only. Resolve the source with `client_patch.py which` and rebuild after a
  bundle update.
- No exe or DLL content. No partial DBC. No vendor asset without a license, source, and hash.
- Client artifacts are binary: `*.MPQ`, `*.mpq`, `*.dbc`, `*.blp`, `*.m2`, `*.skin`, `*.anim` are
  marked binary in `.gitattributes`. The `fix-journal-white-models` branch applies the same rule for
  `patch-Y`; verify `git hash-object --path=<path> <file>` equals `--no-filters`.
- Item.dbc rows mirror the server `item_template` row: class, subclass, material, display, inventory,
  sheathe. A display ID must exist in ItemDisplayInfo.dbc.
- Every patch has its build inputs, `build.py`, `dist/patch-<X|Y|Z>.MPQ`, `manifest.json`, and a
  README with source hashes, install, test, and rollback steps.
- The owner installs and tests; agents do not write to the live client.

## Adding a patch

Create `data/client-patches/<feature>/` with its own README, build script, source, and manifest.
`build.py` must regenerate any derived data, pack MPQ v1 with listfile/attributes/zlib, verify every
entry, and write the manifest. Add the row above in the same change.
