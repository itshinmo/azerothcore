# Client patches

Project client artifacts for the supported 3.3.5a client. Contract:
`feat/map-poi:specs/client-patch.md` (unmerged). Decision: ADR-027.

This branch predates the contract's root index on `local-server-setup`; the row below is the local
addition. On merge, combine the rows from every branch; do not replace the other lists.

## Ledger

- [race-class-combos](race-class-combos/README.md) — `race-class-combos/dist/patch-V.MPQ`:
  character-creation DBCs for the proposed extended race/class pairs. `CharBaseInfo.dbc` 62 -> 67
  rows, `CharStartOutfit.dbc` 126 -> 134 rows; 2 DBCs; SHA256
  `50e4477b93678272ad35089bfbbd6c8fa7f884c98d1d3171491b29da49d4731c`.

Project archive family on the English client: `patch-X` item data (the only `Item.dbc` carrier),
`patch-Y` white preview models, `patch-Z` map/UI. `patch-V` is a proposed character-creation DBC
carrier outside that family; the client-patch owner must approve it. All load after Reforged
`patch-U`; V < X < Y < Z.

## Rules

- Whole-file replacement only; resolve the source with `client_patch.py which` and rebuild after a
  bundle update.
- Every patch has its build inputs, `build.py`, `dist/patch-<letter>.MPQ`, `manifest.json`, and a
  README with source hashes, install, test, and rollback steps.
- MPQ archives and DBC files are binary: `.gitattributes` keeps them out of text normalization
  (`*.MPQ`, `*.mpq`, `*.dbc`, `*.DBC`, `*.blp`, `*.m2`, `*.skin`, `*.anim`,
  `data/client-patches/** -text`).
- No exe or DLL content. No vendor asset without a license, source, and hash.
- The owner installs and tests; agents do not write to the live client.

## Merge note

`specs/client-patch.md`, `tools/client-patch/`, ADR-027, and the full root index are unmerged work on
`feat/map-poi` and `local-server-setup`. When the branches meet, combine the ledger rows and keep the
binary `.gitattributes` rules. If the contract assigns character-creation DBCs a different archive
letter, rename `patch-V` in the ledger, manifest, README, and RFC together.
