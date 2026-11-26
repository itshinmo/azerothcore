# tools/client-patch

StormLib-backed tooling for 3.3.5a client patch MPQs. Contract:
[specs/client-patch.md](../../specs/client-patch.md). Decisions:
[ADR-027](../../decisions/ADR-027-client-patch-pipeline.md).

## Setup

```bash
brew install stormlib
export STORMLIB=/opt/homebrew/lib/libstorm.dylib   # only when the default path is missed
```

`mpq.py` looks for `STORMLIB`, then Homebrew's `/opt/homebrew` and `/usr/local` paths, then the
dynamic loader name.

## Commands

```bash
python3 tools/client-patch/client_patch.py inspect  Data/patch-Z.MPQ
python3 tools/client-patch/client_patch.py list     Data/patch-Z.MPQ --internal
python3 tools/client-patch/client_patch.py which    ~/Games/wotlk-clean/Data 'Interface\FrameXML\WorldMapFrame.lua'
python3 tools/client-patch/client_patch.py extract  Data/patch-Z.MPQ /tmp/out 'Interface\FrameXML\WorldMapFrame.lua'
python3 tools/client-patch/client_patch.py pack     /tmp/patch-Z.MPQ /tmp/root
python3 tools/client-patch/client_patch.py verify   /tmp/patch-Z.MPQ --manifest /tmp/manifest.json --verbose
python3 tools/client-patch/client_patch.py manifest /tmp/patch-Z.MPQ --out /tmp/manifest.json

python3 tools/client-patch/item_dbc.py inspect --dbc Item.dbc --ids 901001-901020
python3 tools/client-patch/item_dbc.py edit --dbc Item.dbc --items items.json --out Item.dbc.new
python3 tools/client-patch/item_dbc.py build --client ~/Games/wotlk-clean \
  --items data/client-patches/item-data/items.json \
  --out data/client-patches/item-data/dist/patch-X.MPQ \
  --manifest data/client-patches/item-data/manifest.json \
  --server-dbc ~/wow/Data/dbc/Item.dbc
python3 data/client-patches/item-data/generate_items.py --check
```

`which` models the English client by default. Use `--order localized` for the Russian/Chinese shape;
the project does not ship to those clients yet.

## Rules

- Project family: `patch-X` item data (only Item.dbc), `patch-Y` white models (owned by
  `fix-journal-white-models`), `patch-Z` map/UI.
- MPQ v1, zlib, listfile, attributes. No exe or DLL content.
- Whole-file replacement only. Resolve the highest-priority source below the carrying project archive
  with `which`.
- Never ship a partial DBC. Record client and server DBC hashes in the manifest.
- Item.dbc: 8 fields, 32-byte rows, sorted IDs, display IDs present in ItemDisplayInfo.dbc. A
  missing ItemDisplayInfo.dbc fails unless an offline fixture uses `--no-display-check`.
- A full server Item.dbc replacement runs `--server-dbc` and fails on server-only IDs or conflicts;
  `item_dbc` table rows are a separate deployment path.
- Paths are normalized to backslashes; `..`, absolute paths, drive letters, NUL, and symlink escapes
  are rejected on add and extract.
- Third-party assets need a license, source, and hash. v1 uses stock icons only.

## Tests

```bash
python3 -m unittest discover -s tools/client-patch/tests -v
```

Archive tests skip cleanly when StormLib is absent; path-safety and load-order tests still run.

## Feature builds

Worked examples:

- `data/client-patches/map-pins/build.py` — appends the FrameXML canary, packs `patch-Z` with the
  `WorldMapPins` addon and the Cooldown nil guard, verifies, writes the manifest.
- `data/client-patches/item-data/build.py` — validates `items.json` against the frozen world-treasure
  sources, upserts Item.dbc rows, checks display IDs, packs `patch-X` with only Item.dbc, verifies,
  writes the manifest.
