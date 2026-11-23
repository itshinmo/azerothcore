# Client patches

Project client artifacts for the supported 3.3.5a client. Contract:
[`specs/client-patch.md`](../../specs/client-patch.md) (unmerged, branch `feat/map-poi`). Decision:
ADR-027.

## Ledger

- [white-boss-models](white-boss-models/README.md) — `white-boss-models/dist/patch-Y.MPQ`: stock
  3.3.5a goblin male model, its 3 skins and 32 external animations. SHA256
  `b236c1c35d2714a0e6423e87a934256fbace13168951d2c5144b0ca30016f524`; 0 DBC files.

Project archive family on the English client: `patch-X` item data (the only `Item.dbc` carrier),
`patch-Y` white preview models, `patch-Z` map/UI. All load after Reforged `patch-U`; X < Y < Z.

## Rules

- Whole-file replacement only; resolve the source with `client_patch.py which` and rebuild after a
  bundle update.
- Every patch has its build inputs, `build.py`, `dist/patch-<X|Y|Z>.MPQ`, `manifest.json`, and a
  README with source hashes, install, test, and rollback steps.
- MPQ archives and DBC files are binary: `.gitattributes` must keep them out of text normalization
  (`*.MPQ`, `*.mpq`, `*.dbc`, `*.DBC`, `data/client-patches/** -text`).
- No exe or DLL content. No vendor asset without a license, source, and hash.
- The owner installs and tests; agents do not write to the live client.

## Merge note

This file is also created by the map/POI branch (`item-data`, `map-poi` rows). Combine the rows when
the branches meet; do not replace either list.
