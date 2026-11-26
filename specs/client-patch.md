# Client patch

## Purpose

Define how the project builds, verifies, installs, and rolls back a client-side patch for the
supported 3.3.5a client. The pipeline is data-only and reproducible from the repository.

One artifact sits outside the MPQ family: the `DivxDecoder.dll` proxy authorized by
[ADR-036](../decisions/ADR-036-client-dll-patches.md). It is not packed into a project archive and it
is not a general executable-patch mechanism; see Security.

## Scope

`tools/client-patch/`, `data/client-patches/`, the project `patch-X/Y/Z.MPQ` family, load-order resolution,
whole-file replacement, the manifest, and the in-client canary. Does not own individual feature
content; a feature spec or ADR owns what a patch contains.

## Boundary

Owns the archive mechanics and the load-order contract. Does not own the client bundle
([client-bundle.md](../runbook/operation/client-bundle.md)), server content
([content-pipeline.md](content-pipeline.md)), or the supported client executable. Client patches do
not bypass server authority, RBAC, or audit.

## Contract

### Archive and naming

The project uses a three-archive family, split by data domain rather than one letter per feature:

| Archive | Domain | DBC |
|---------|--------|-----|
| `Data/patch-X.MPQ` | item data | the **only** carrier of `DBFilesClient\Item.dbc` |
| `Data/patch-Y.MPQ` | white dungeon/raid preview models, owned by `fix-journal-white-models` (batch 1: stock goblin male) | none |
| `Data/patch-Z.MPQ` | map/UI (`ServerMapPOI`) + `Cooldown.lua` nil guard | none |

- Each archive is MPQ v1, zlib, `(listfile)` and `(attributes)` present.
- `.gitattributes` marks `*.MPQ`, `*.mpq`, `*.dbc`, `*.blp`, `*.m2`, `*.skin` and `*.anim` binary;
  the repository-wide `* text eol=lf` must not touch them. Verify with
  `git hash-object --path=<path> <file>` vs `--no-filters`.
- Vendor archives (`patch-A..U`, locale archives, base archives) are never modified.
- X, Y and Z each load after Reforged `patch-U`; alphabetically X < Y < Z. Only X carries Item.dbc,
  so no whole-file DBC conflict exists. A second project archive carrying the same DBC is a build
  error.
- `patch-Y` is built and checked in by the `fix-journal-white-models` branch; its manifest records
  SHA256 `b236c1c35d2714a0e6423e87a934256fbace13168951d2c5144b0ca30016f524`. This branch does not
  rebuild or overwrite it.
- The family is English-client only until a localized variant is built and tested.

### Load order

The English 3.3.5 client resolves files low to high in this order:

1. Locale non-patch archives (`base-enUS`, `locale-enUS`, expansion/lichking locale and speech,
   backup).
2. Locale numeric patches (`patch-enUS`, `patch-enUS-2` … `patch-enUS-9`).
3. Locale alphabetic patches (`patch-enUS-A` … `patch-enUS-Z`).
4. Base non-patch archives (`common`, `common-2`, `expansion`, `lichking`).
5. Base numeric patches (`patch`, `patch-2` … `patch-9`).
6. Base alphabetic patches (`patch-A` … `patch-Z`).

Therefore `Data/patch-Z.MPQ` is the highest-priority archive on the verified English bundle, and
`Data/patch-X.MPQ` outranks every vendor archive for Item.dbc. The Russian/Chinese shape puts locale
patches last; `--order localized` models that chain, and the project does not ship to those clients
yet.

`client_patch.py which <Data> <path>` reports the winner and every lower archive that contains the
path. It exits non-zero when no archive contains the path. Unreadable archives (for example an
encrypted third-party patch) are listed as skipped, not treated as containing the file.

### Whole-file replacement

MPQ v1 replaces a file; it does not patch bytes inside it. The build must:

1. resolve the highest-priority source **below the carrying project archive** with `which`;
2. extract that file whole;
3. apply the project change (append a Lua block, edit the whole file, replace the whole DBC);
4. pack the result under the same archive path.

Never ship a partial DBC. Never extract a vendor asset into a project patch without a recorded
license, source, and hash. `patch-X` ships the whole Item.dbc: the vendor source rows plus the
custom rows from `items.json`, sorted by ID.

### DBC rule

- Client source of truth: the highest-priority archive for `DBFilesClient\<Name>.dbc`.
- Server source of truth: `DataDir/dbc/<Name>.dbc`.
- A DBC change updates the client patch and the server `DataDir`, and records both SHA256 values in
  the manifest. Rebuild after a client bundle update. Item.dbc ships the same bytes as
  `data/client-patches/item-data/dist/Item.dbc` for `DataDir/dbc/Item.dbc`, or the same rows through
  the `item_dbc` table; choose one path and do not half-apply.
- Item.dbc is validated as 8 fields per row, 32 bytes per row, IDs sorted, and every custom
  `DisplayInfoID` present in the client's ItemDisplayInfo.dbc (read-only check). A missing display is
  the red-question-mark failure.
- The map-POI `patch-Z` changes **zero** DBC files (`"dbc_files": 0`). The item-data `patch-X`
  changes exactly one (`"dbc_files": 1`) and carries no other file.

### Manifest

`manifest.json` lives next to the patch and carries:

| Field | Meaning |
|-------|---------|
| `schema` | Manifest format, currently `1`. |
| `archive`, `sha256`, `size`, `format`, `compression` | The built archive. |
| `built_at` | UTC build time. A rebuild changes the manifest timestamp; unchanged sources rebuild the archive byte-identically. |
| `dbc_files` | Number of DBCs replaced: `0` for map-poi, `1` for item-data. |
| `dbc` | DBC source/output hashes, row counts, fields, record size, added/updated IDs. |
| `items` | Item.dbc custom rows written (item-data only). |
| `items_sha256` | SHA256 of the item source JSON (item-data only). |
| `server_dbc` | Server-side copy path, SHA256 and row count (item-data only). |
| `server_dbc_input` | Server DataDir Item.dbc hash, rows, server-only IDs, conflicts when `--server-dbc` was used. |
| `load_order` | Client, locale, order, project family, canary/source archive and hashes, expected winner, source chain. |
| `poi_sources` | Generated POI input DBC archive and SHA256, snapshot date (map-poi only). |
| `sources` | Each packed path, its repository source or canary source, and SHA256. |
| `entries` | Each packed path, sizes, SHA256, and StormLib verify flags. |

`verify --manifest` fails when the archive hash, entry list, entry hash, or StormLib checksum differs.

### Tools

| Command | Contract |
|---------|----------|
| `inspect ARCHIVE` | Format, size, SHA256, listfile/attributes/signature presence, file count. |
| `list ARCHIVE` | Entries with sizes; `--internal` includes `(listfile)` etc. |
| `which DATA PATH` | Highest-priority archive and full source chain. |
| `extract ARCHIVE DEST [PATH...]` | Safe extraction; `--all`, `--force`. |
| `pack OUT SOURCE[:PREFIX]...` | Create MPQ v1 with listfile, attributes, zlib. |
| `verify ARCHIVE [--manifest FILE]` | StormLib checksums plus manifest comparison. |
| `manifest ARCHIVE --out FILE` | Write an entry manifest. |
| `item_dbc.py inspect --dbc FILE` | Validate Item.dbc and print rows; `--archive` reads it from an MPQ. |
| `item_dbc.py edit --dbc IN --items JSON --out OUT` | Upsert rows and sort; no MPQ write. |
| `item_dbc.py build --client DATA --items JSON --out MPQ --manifest FILE [--server-dbc FILE]` | Build patch-X with only Item.dbc; fail on server-only IDs. |
| `generate_items.py --check` | Validate items.json against the frozen batch CSV, item_template SQL and item_dbc mirror. |

### Export and discovery

- `data/client-patches/README.md` indexes every patch.
- `data/client-patches/<feature>/` holds its build inputs, `build.py`, `dist/patch-<X|Y|Z>.MPQ`,
  `manifest.json`, and `README.md` with source archive, source hashes, install, test, and rollback
  steps.
- Build outputs are local (`build/`); the patch and manifest are tracked so a client can be rebuilt.

## Errors and edge cases

- **No listfile:** `list` falls back to reading `(listfile)` explicitly; if that is missing, names
  cannot be enumerated. `which` still works because hash lookup does not need a listfile.
- **Encrypted archive:** skipped by `which` and reported; never silently treated as a source.
- **Case:** paths are case-insensitive in the client. The tool normalises to backslashes but does not
  lowercase; duplicate paths with different case are a build error.
- **Path traversal:** `..`, absolute paths, drive letters, NUL, and symlink escapes are rejected on
  add and extract. Extraction resolves the destination and requires it to stay below the root.
- **Delete markers:** MPQ `MPQ_FILE_DELETE_MARKER` entries are not supported by the project build;
  do not use them.
- **Stale source:** if a project archive is already installed, the build takes the highest source
  below it; if no source remains, the build fails instead of copying its own output.
- **Item.dbc header mismatch:** Item.dbc must be 8 fields and 32-byte rows. Any other shape is
  rejected, not guessed.
- **Missing display:** a custom row whose `DisplayInfoID` is absent from ItemDisplayInfo.dbc fails
  the build; that is the red question mark.
- **DBC conflict:** if Item.dbc is already carried by `patch-Y` or `patch-Z`, the build fails; X
  would not win.
- **Server-only Item.dbc row:** with `--server-dbc`, a row absent from the client union fails the
  build. Add it to `items.json` or keep the server file and use `item_dbc` rows; never drop it.
- **items.json drift:** a mismatch against the checked-in item_template/CSV/item_dbc sources fails
  `build.py --check`; run `generate_items.py --write` and review the diff.
- **Client update:** a bundle update that changes an overridden file invalidates the source hash.
  Rebuild and re-verify; do not reuse the old archive.

## Security

- No secrets, credentials, player data, or internal hostnames in patches, manifests, or docs.
- No executable content in an MPQ: no exe, DLL, or code; data and Lua/XML only.
- **One exception, outside MPQ:** the `DivxDecoder.dll` proxy authorized by
  [ADR-036](../decisions/ADR-036-client-dll-patches.md). It is not packed in a project archive; it
  sits beside the executable, is built from tracked source, and is pinned by hash in the launcher
  manifest. No second executable artifact is permitted without its own ADR.
- No vendor assets without a license, source, and hash.
- Client patches do not grant items, change RBAC, or bypass server checks.
- Agents never write to the live client; the owner installs and tests.

## Observability

- `client_patch.py verify` prints per-entry status and a final failure count.
- `item_dbc.py inspect` prints the Item.dbc header, row count, sort state, and selected rows.
- The canary prints one login line from the overridden FrameXML file.
- The map addon prints one load line and hides on map close.
- The manifest is the audit record: what was packed, from which source, and with which hashes.

## References

- [ADR-027](../decisions/ADR-027-client-patch-pipeline.md)
- [ADR-032](../decisions/ADR-032-map-poi-layer.md)
- [runbook/operation/client-patch.md](../runbook/operation/client-patch.md)
- [runbook/operation/client-bundle.md](../runbook/operation/client-bundle.md)
- [content-pipeline.md](content-pipeline.md)
