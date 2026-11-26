---
name: client-patch
description: Use when a feature needs a 3.3.5a client-side change (Lua/XML, map layer, client DBC), when building or verifying patch-X/Y/Z.MPQ, or when a client patch does not load and load order must be proven.
---

# client-patch

## Prerequisites

- Read [decisions/ADR-027](../../../decisions/ADR-027-client-patch-pipeline.md),
  [specs/client-patch.md](../../../specs/client-patch.md), and
  [runbook/operation/client-patch.md](../../../runbook/operation/client-patch.md).
- StormLib for archive work: `brew install stormlib`; set `STORMLIB` only when the default is wrong.
- `luajit` for the Lua syntax gate.
- The supported client bundle; the English load-order chain is the tested one.
- Worked examples: [map-pins](../../../data/client-patches/map-pins/README.md),
  [item-data](../../../data/client-patches/item-data/README.md).

## Workflow

1. Resolve every overridden path with `which`; record the source archive and SHA256.
2. Extract the whole file; edit it or append the hook; keep the original prefix.
3. Build with the feature's `build.py`:
   - map/UI: `python3 data/client-patches/map-pins/build.py`
   - item data: `python3 data/client-patches/item-data/build.py [--server-dbc PATH]`
4. Validate the feature sources (item-data):
   `python3 data/client-patches/item-data/generate_items.py --check`.
5. Verify the archive and manifest:
   `python3 tools/client-patch/client_patch.py verify <MPQ> --manifest <manifest> --verbose`.
6. Prove load order with `which` after a simulated install (symlinked `Data` plus the project
   archive); the expected archive must win.
7. Run the Lua syntax gate on every Lua file and the offline addon test for map/UI changes.
8. Write the feature README with source hashes, output SHA256, install, in-client test steps, and
   rollback.
9. Hand the patch to the owner. Do not copy it into the live client.

## Constraints

- MPQ-only. No exe or DLL edits.
- Project family: `patch-X` item data (only Item.dbc), `patch-Y` white models (owned by
  `fix-journal-white-models`), `patch-Z` map/UI. X < Y < Z, all after Reforged `patch-U`.
- This branch does not rebuild or overwrite `patch-Y`.
- Only one archive carries a given DBC. Never ship a partial DBC.
- Whole-file replacement. Resolve the source below the carrying project archive.
- Item.dbc: 8 fields, 32-byte rows, sorted IDs, display IDs present in ItemDisplayInfo.dbc. A full
  server `Item.dbc` replacement must pass the `--server-dbc` union/diff check; `item_dbc` table rows
  are a separate deployment path.
- `SMPOI` v2 requires a server-issued `AUTH` token; without it, dynamic Outlaw markers are off.
  The token stops casual spoofing only, not a modified client.
- No vendor assets without a license, source, and SHA256.
- Agents never install into the live client. The owner tests.
- `.gitattributes` must keep `*.MPQ`, `*.mpq`, `*.dbc`, `*.blp`, `*.m2`, `*.skin`, `*.anim` binary.

## Useful commands

```bash
python3 tools/client-patch/client_patch.py inspect <MPQ>
python3 tools/client-patch/client_patch.py which <Data> 'DBFilesClient\Item.dbc'
python3 tools/client-patch/client_patch.py verify <MPQ> --manifest <manifest> --verbose
python3 tools/client-patch/item_dbc.py inspect --archive <MPQ> --ids 901001-901020
python3 data/client-patches/item-data/generate_items.py --check
python3 data/client-patches/map-pins/build.py --check
luajit data/client-patches/map-pins/tests/test_addon.lua
python3 -m unittest discover -s tools/client-patch/tests -v
```

## Expected output

- A verified `data/client-patches/<feature>/dist/patch-<X|Y|Z>.MPQ` with matching manifest.
- `which` naming the project archive as the winner for every overridden path.
- Feature README with install, test, rollback, and hashes.
- No live-client or server writes by the agent.

## References

- [ADR-027](../../../decisions/ADR-027-client-patch-pipeline.md)
- [ADR-032](../../../decisions/ADR-032-map-poi-layer.md) (withdrawn)
- [ADR-037](../../../decisions/ADR-037-world-map-pins.md)
- [specs/client-patch.md](../../../specs/client-patch.md)
- [runbook/operation/client-patch.md](../../../runbook/operation/client-patch.md)
- [client bundle](../../../runbook/operation/client-bundle.md)
