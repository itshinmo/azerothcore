# ADR-027 — Client-patch pipeline: MPQ-only, whole-file replacement, load order

- Status: accepted
- Date: 2026-11-23
- [ADR-036](ADR-036-client-dll-patches.md) (proposed) would permit one reviewed `DivxDecoder.dll`
  proxy outside the MPQ family. Until it is accepted, this ADR stands unamended.
- Related: [ADR-002](ADR-002-custom-content-isolation-and-ids.md),
  [ADR-013](ADR-013-server-and-client-before-website.md),
  [ADR-020](ADR-020-collections-transmog-stack.md),
  [ADR-026](ADR-026-transmog-npc-only-and-preview.md),
  [ADR-037](ADR-037-world-map-pins.md)

## Context

Some client behavior cannot be fixed by server data. The mount/transmog preview is UI-only and the
3.3.5 client lacks a slot-targeted `DressUpModel:TryOn` ([ADR-026](ADR-026-transmog-npc-only-and-preview.md)).
The character-creation armor toggle lives in `Interface\GlueXML` inside a vendor MPQ. The classic
instance map gap is a client `DungeonMap.dbc` gap. Map POIs from the server `points_of_interest` table
are minimap markers only.

The verified client is a specific bundle: WoWSilicon's exe and `d3d9.dll`, Ascension `patch-A.MPQ`,
and Reforged `patch-B..U.MPQ` ([client bundle](../runbook/operation/client-bundle.md)). The project
does not own those files. A patch pipeline that edits the exe or a vendor MPQ would fight the
launcher, break its hash checks, and be impossible to rebuild from the repository.

## Decision

1. **MPQ-only v1. No exe or DLL edits.** Client patches are data archives. They do not patch
   `Wow.exe`, `d3d9.dll`, `libDllLdr.dll`, or any other executable. A feature that truly needs code
   is out of scope until a separate decision says otherwise.
2. **Project archive family `patch-X/Y/Z.MPQ` for the English client.** Vendor patches stay
   untouched. The family is split by data domain, not one letter per feature:
   - `patch-X.MPQ` — item data; the **only** carrier of `DBFilesClient\Item.dbc`.
   - `patch-Y.MPQ` — white dungeon/raid preview models, owned by the parallel
     `fix-journal-white-models` branch. Batch 1 restores the stock goblin male model
     (`Character\Goblin\Male\*`) over the broken Ascension HD conversion. Archive
     `fix-journal-white-models:data/client-patches/white-boss-models/dist/patch-Y.MPQ`, manifest
     `data/client-patches/white-boss-models/manifest.json`; archive SHA256
     `b236c1c35d2714a0e6423e87a934256fbace13168951d2c5144b0ca30016f524`, 616,530 bytes. This
     branch cross-references it and does **not** rebuild or overwrite Y.
   - `patch-Z.MPQ` — map/UI (the `WorldMapPins` addon, its FrameXML canary and the `Cooldown.lua`
     nil guard).
   X, Y and Z each load after Reforged `patch-U`; alphabetically X < Y < Z. Only X carries Item.dbc,
   so there is no whole-file DBC conflict: Z is the highest-priority map/UI archive, and X wins
   Item.dbc because no higher archive carries it. Y is a model-file patch from its own branch; do
   not merge its archive into this family or rebuild it here. On the English 3.3.5 client the base
   alphabetic patches load last and outrank `patch-enUS-3.MPQ`; on Russian and Chinese clients the
   locale chain loads last, so a root X/Y/Z would not win there. Do not ship the project family to a
   non-English client until a locale-named variant is built and tested.
3. **Whole-file replacement.** MPQ v1 has no partial file override. Every file a patch changes is
   extracted from its **highest-priority source below the project archive that carries it**,
   modified, and packed whole. For Lua, the source file is copied and the change appended or hooked.
   For a DBC, the whole table is replaced. A partial DBC is never shipped. A second project archive
   carrying the same DBC is a build error.
4. **Source-of-truth DBC rule.** The client source is the highest-priority archive containing
   `DBFilesClient\<Name>.dbc`, resolved with `client_patch.py which`, excluding the project archive
   that will carry the replacement. The server source is `DataDir/dbc/<Name>.dbc`; for item data the
   server `item_template` row is the gameplay source, and the client Item.dbc row must mirror its
   class, subclass, material, display, inventory and sheathe fields. The server also loads Item.dbc
   (`sItemStore`), so the same bytes are published as `data/client-patches/item-data/dist/Item.dbc`
   for `DataDir/dbc/Item.dbc`, or the same rows go through the item_dbc table; choose one and do not
   half-apply. The `item_dbc` table is a separate deployment path, not a full server Item.dbc
   replacement. A full replacement runs `--server-dbc`: server-only IDs or same-ID conflicts abort
   the build, because a blind overwrite would drop them. A DBC change updates both and records both
   hashes in the patch manifest. Rebuild after every client bundle update.
   `patch-X` is the first DBC carrier: it ships the **whole** Item.dbc, never a row fragment. Map/UI
   `patch-Z` ships no DBC.
5. **Tools live in `tools/client-patch/`.** `mpq.py` wraps StormLib (open/list/read/extract, create/
   add, verify, safe paths). `client_patch.py` exposes `inspect`, `list`, `which`, `extract`, `pack`,
   `verify`, and `manifest`. `which` resolves the English or localized load-order chain and reports
   every archive that contains the path, lowest to highest, with the winner marked.
6. **Third-party pack policy.** Vendor packs are inputs, not sources. The project patch contains
   only project-authored Lua/XML and project data. Assets copied from another pack require a recorded
   license, source URL, and SHA256; no vendor asset is extracted into a project patch merely because
   it is convenient. v1 uses stock client icons and no custom BLP.
7. **Ledger and manifest.** Every client feature lives in `data/client-patches/<feature>/` with its
   source, build script, its `dist/patch-<X|Y|Z>.MPQ`, `manifest.json`, and README. The manifest
   records the archive SHA256 and size, every entry with its SHA256, the source archive and hash,
   the load-order assumption, the DBC count, and the build date. An Item.dbc manifest also records
   rows before/after, every added/updated item ID, the 8-field/32-byte validation, and the display-ID
   check. `data/client-patches/README.md` indexes the patches.
8. **Server authority is unchanged.** A client patch cannot grant items, change permissions, or
   bypass RBAC. Server checks and audit stay server-side. The patch may draw information the server
   already sends, or bake published world data.
9. **Verification before install.** `client_patch.py verify --manifest` reads every entry, checks
   StormLib checksums, and compares SHA256 values. `which` is run against the client `Data` tree
   before and after install. A canary in an overridden FrameXML file proves load order in the client.
   An Item.dbc patch is additionally checked with `item_dbc.py inspect`: 8 fields, 32-byte rows,
   sorted IDs, every custom display ID present in the client ItemDisplayInfo.dbc. Agents never install
   into the live client; the owner tests and reports.
10. **Rollback is deleting the archive.** A project archive has no installer and no registry state.
    Removing it restores the previous client behavior. If the matching server `DataDir/dbc/Item.dbc`
    or the `item_dbc` rows were deployed, restore them from the pre-change backup and restart; the
    map/UI patch needs no server rollback.
11. **Client artifacts are binary in Git.** `.gitattributes` marks `*.MPQ`, `*.mpq`, `*.dbc`,
    `*.blp`, `*.m2`, `*.skin`, and `*.anim` binary before the repository-wide `* text eol=lf` can
    normalize them. Verify each artifact with
    `git hash-object --path=<path> <file>` equal to `git hash-object --no-filters <file>`. Git
    prints a SHA-1 object ID there; the manifest records the SHA-256 content hash, so compare the
    latter with `shasum -a 256`, not with the Git object ID. The parallel
    `fix-journal-white-models` branch applies the same rules to `patch-Y.MPQ`.

## Alternatives considered

- **Loose addon in `Interface/AddOns`.** Rejected as the delivery format: it is a user addon, it is
  lost on a client rebuild, and it cannot override FrameXML or DBCs. Loose addons stay a development
  aid only.
- **Exe or DLL patch.** Rejected. WoWSilicon owns the executable and its d3d9 chain, re-applies its
  game patch on hash mismatch, and a binary patch cannot be reviewed or rebuilt from this repository.
- **One patch letter per feature.** Rejected: letters are a finite, global namespace and two
  features would depend on each other's letters. The X/Y/Z family is split by data domain, and only
  one archive carries a given DBC.
- **Partial DBC or a DBC overlay table.** Not possible with MPQ v1 replacement semantics; the server
  and client would disagree about the table.
- **CASC or a launcher.** Not available on 3.3.5a. A launcher is a later launch-phase question.

## Consequences

- A feature's client change is reproducible from the repository: sources, build script, manifest,
  and hashes.
- The project archives must be rebuilt when the client bundle changes a file they override. The
  manifest names the source archive and hash, so staleness is visible.
- The patch is English-client only until a localized variant is tested.
- Client patches remain data-only; code-level client defects stay open or need a new decision.
- Every UI patch adds a canary and a documented in-client test; a DBC patch is verified by entry
  hashes, a row-level DBC check, and an in-client item display test. The owner remains the verifier.

## References

- [specs/client-patch.md](../specs/client-patch.md)
- [runbook/operation/client-patch.md](../runbook/operation/client-patch.md)
- [data/client-patches/README.md](../data/client-patches/README.md)
- `tools/client-patch/`
