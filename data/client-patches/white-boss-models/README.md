# White boss models — stock goblin male overlay (`patch-Y.MPQ`)

Status: built, conforms to the client-patch contract (unmerged, `feat/map-poi`), installed on the
owner's client and awaiting the in-game pass.

The Journal dungeon/raid cards render some bosses white/untextured. Gilnid (creature 1763) was the
first confirmed case. This patch restores the stock 3.3.5a goblin male model over the broken HD
replacement shipped by the Ascension character pack. It fixes Gilnid and four other Journal bosses,
plus every other goblin male NPC in the world, without touching any DBC.

## Root cause

The Ascension pack `patch-A.MPQ` (Nexus mod 907, "Ascension Character Customization") replaces
`Character\Goblin\Male\GoblinMale.m2` with a converted HD model whose texture mapping is wrong: most
of the body is batched onto the character **hair** slot (type 6) and part onto the **cape** slot
(type 2), instead of the **skin** slot (type 1) that receives the baked NPC texture. The goblin bake
therefore only reaches about a third of the model; the rest has no goblin texture and draws white.
The stock model in `common-2.MPQ` is intact.

Measured on `patch-A.MPQ`'s `GoblinMale.m2` + `GoblinMale00.skin` (vertex share per texture entry):

| Texture entry | Type | Slot | Vertices |
|---|---|---|---|
| 1 | 6 | character hair | 9,236 (61.9%) |
| 0 | 1 | skin — receives the baked NPC texture | 5,095 (34.1%) |
| 3 | 2 | cape / object skin | 564 (3.8%) |
| 8 | 0 + filename | doodad `RAG_01.BLP` | 26 (0.2%) |
| 2 | 0 + filename | eye glow | 8 (0.05%) |

All 14,929 vertices are batched; there is no unassigned group. An earlier draft of this document
described a "no cape" cause and a 572-vertex unassigned entry; both were measurement errors and are
removed.

Evidence chain:

1. `creature_template_model` 1763 → display 7124
   (`data/sql/base/db_world/creature_template_model.sql`).
2. `CreatureDisplayInfo.dbc` 7124 → ModelID **831**, ExtendedDisplayInfoID **4819**, texture
   variations 0/0/0.
3. `CreatureModelData.dbc` 831 → `Character\Goblin\Male\GoblinMale.mdx` (the client loads `.m2`).
4. Model providers: `common-2.MPQ` (stock) and `patch-A.MPQ` (HD replacement). patch-A loads later
   in the client chain, so it wins.
5. `CreatureDisplayInfoExtra.dbc` 4819 → `Textures\BakedNPCTextures\CreatureDisplayExtra-04819.blp`,
   present in patch-A, a valid 512×512 DXT1 goblin bake.
6. Stock alternative: `GoblinMale.m2`, `GoblinMale00..02.skin` and 32 `.anim` files, all present in
   `common-2.MPQ`.

The baked NPC texture only fills the type-1 skin slot. That is why the 61.9% on the hair slot and
3.8% on the cape slot render white, while the 34.1% on the skin slot keeps the goblin bake.

## Affected Journal bosses

Scanned from `instance_encounters` → `creature_template_model` → display → model, then checked
against every archive. Only these resolve to the broken model:

| Creature | Boss | Display | Model |
|---|---|---|---|
| 643 | Sneed | 7125 | 831 |
| 647 | Captain Greenskin | 7113 | 831 |
| 1763 | Gilnid | 7124 | 831 |
| 9543 | Ribbly Screwspigot | 8667 | 831 |
| 13601 | Tinkerer Gizlock | 7125 | 831 |

No Journal boss that resolves to a creature display is missing its model file or its baked NPC
texture. Sixteen encounter rows (Mal'ganis, Valithria Dreamwalker, Gunship Battle, ...) name entries
that are not creature templates in the base world database, so they have no display to check; they
are not white-model cases. Anything else the owner reports as white belongs to a different batch
(see [LEDGER.md](LEDGER.md)).

## The patch

`dist/patch-Y.MPQ` — 36 files, 616,530 bytes, sha256
`b236c1c35d2714a0e6423e87a934256fbace13168951d2c5144b0ca30016f524`.

Every entry is the stock 3.3.5a file from `common-2.MPQ`:

- `Character\Goblin\Male\GoblinMale.m2`
- `Character\Goblin\Male\GoblinMale00.skin`
- `Character\Goblin\Male\GoblinMale01.skin`
- `Character\Goblin\Male\GoblinMale02.skin`
- `Character\Goblin\Male\GoblinMale<0062,0064...0129>-00.anim` — the 32 external animations the
  stock client ships for this model. They must ship too: patch-A overrides all 32 with HD animations
  for the HD skeleton.

Path list and every hash: [manifest.json](manifest.json).

## Sources and license

- `common-2.MPQ`, source of every patched file (stock 3.3.5a):
  `9c605d95443172bdfd7c6936bc636684761241657935c22da25f955083809f43`
- `patch-A.MPQ`, carries the broken replacement:
  `992b5f3e6badc960b2eb68b976f5be42ae5f1e1416ccb43833fbbc6cfe6c2b94`
- `patch-C.mpq`, effective `CreatureDisplayInfo.dbc` and `CreatureModelData.dbc`:
  `8fdf961feaf1bcd8231d1ad4034f1518df812d3a4c4730544cae447f234d8265`

Inner DBC hashes, from `patch-C.mpq`:

- `CreatureDisplayInfo.dbc` `cc57b8653fd1e0a586fe4b6e46d06cb4bf42138a99d6763dfc367caeb906ed53`
- `CreatureModelData.dbc` `b02d504fb1c77393f2e579b3e59ce762db9c8cc2a33f042d7b499e80d0757733`

Broken asset hashes, for the record: `patch-A.MPQ` `Character\Goblin\Male\GoblinMale.m2`
`0975b032999eadb5c914eebe0f8e2ad64ff3bc7f2c92a1ff5eb23ea4c1dec6a2`, skin `GoblinMale00.skin`
`f01d798d2d0dd7257ec5ea97a45a67a0cd854dfcc0524eb026ce33c375728807`, baked texture
`CreatureDisplayExtra-04819.blp` `53977bac620071db0c04a99cd1e4f71eb38ad3accc60c8536982d442fc98920f`.

License: the packed files are the stock 3.3.5a client assets from the owner's own licensed install.
No Ascension or Reforged asset is redistributed, and no third-party content is introduced. The patch
is a byte-identical copy of Blizzard files the client already owns, repacked so the client can read
them again.

## Load order

The English 3.3.5a client resolves files low to high in one chain: locale non-patch archives, locale
numeric patches, locale alphabetic patches, base non-patch archives (`common`, `common-2`,
`expansion`, `lichking`), base numeric patches, then base alphabetic patches `patch-A` … `patch-Z`.
Later archives win. `patch-Y` therefore sits above every vendor archive and below the reserved
`patch-Z`.

Proven against the owner's installed client with the project tool (data paths abbreviated):

```text
$ python3 tools/client-patch/client_patch.py which ~/Games/wotlk-clean/Data 'Character\Goblin\Male\GoblinMale.m2'
Character\Goblin\Male\GoblinMale.m2
  winner: ~/Games/wotlk-clean/Data/patch-Y.MPQ
  sources (low to high):
     ~/Games/wotlk-clean/Data/common-2.MPQ
     ~/Games/wotlk-clean/Data/patch-A.MPQ
   > ~/Games/wotlk-clean/Data/patch-Y.MPQ
```

`patch-Z.MPQ` is reserved by the map/POI branch and loads after this patch. The two patches do not
share a path today. If a future batch ever adds a `patch-Z` entry that collides with a path here,
record the collision in the ledger and stop; do not merge them silently.

## Contract and layout

This directory follows `specs/client-patch.md` (unmerged, branch `feat/map-poi`, ADR-027):

```text
data/client-patches/white-boss-models/
  build.py          reproducible builder; pins source archive and every entry hash
  dist/patch-Y.MPQ  the artifact
  manifest.json     schema 1 manifest (format, compression, built_at, dbc_files, load_order, sources, entries)
  README.md
  LEDGER.md
```

The manifest is accepted by the pipeline verifier:

```text
$ python3 tools/client-patch/client_patch.py verify dist/patch-Y.MPQ --manifest manifest.json
dist/patch-Y.MPQ: 36 files, ok
```

Exception to record while the contract is unmerged: `build.py` writes the manifest itself instead of
importing `tools/client-patch/`, because that tool is not in this branch. Once `feat/map-poi` merges,
switch the builder to `client_patch.py manifest` and delete the duplicate writer. The artifact layout
and manifest fields already match, so nothing else changes.

## Build and verify

```bash
python3 data/client-patches/white-boss-models/build.py
python3 data/client-patches/white-boss-models/build.py --check
# Requires the client-patch tool from feat/map-poi; skip this command on a branch without it.
python3 tools/client-patch/client_patch.py verify \
    data/client-patches/white-boss-models/dist/patch-Y.MPQ \
    --manifest data/client-patches/white-boss-models/manifest.json
```

The builder pins the source archive hash and every entry hash, packs with StormLib
(`STORMLIB=/opt/homebrew/lib/libstorm.dylib` by default), then extracts every entry back and compares
it byte for byte. File times are pinned, so a rebuild produces the same archive bytes and the same
`sha256`; only `built_at` in the manifest changes.

MPQ archives and DBC files are covered by the `binary` rules in `.gitattributes`
(`*.MPQ`, `*.mpq`, `*.dbc`, `*.DBC`, `data/client-patches/** -text`). Without them `* text eol=lf`
rewrites the six CRLF byte pairs inside the archive and corrupts it. Proof for this artifact:

```text
$ git check-attr binary text diff -- data/client-patches/white-boss-models/dist/patch-Y.MPQ
data/.../patch-Y.MPQ: binary: set
data/.../patch-Y.MPQ: text: unset
data/.../patch-Y.MPQ: diff: unset
$ git hash-object --path=data/client-patches/white-boss-models/dist/patch-Y.MPQ dist/patch-Y.MPQ
e3bda8d05b52082749a9c402ca748fd3bf98bd52          # sha1 object id of the blob git would store
$ git cat-file blob e3bda8d0… | shasum -a 256
b236c1c35d2714a0e6423e87a934256fbace13168951d2c5144b0ca30016f524  # bytes a commit would store
```

## Install and test (owner)

1. Keep a backup copy of any existing `~/Games/wotlk-clean/Data/patch-Y.MPQ`.
2. Check the installed file:
   `shasum -a 256 ~/Games/wotlk-clean/Data/patch-Y.MPQ` must print
   `b236c1c35d2714a0e6423e87a934256fbace13168951d2c5144b0ca30016f524`. If it differs, copy
   `dist/patch-Y.MPQ` again.
3. Restart the client (fully quit; `/reload` does not reload MPQs).
4. Open the Journal → Dungeons → The Deadmines → Gilnid. Expected: textured goblin, no white body,
   no Lua errors. Repeat for Sneed and Captain Greenskin; optionally Ribbly Screwspigot (Blackrock
   Depths) and Tinkerer Gizlock (Maraudon).
5. Visit a goblin NPC in the world (for example the Deadmines Goblin Foundry) and confirm the same
   textured model.
6. Check that goblin animations still play (walk, attack, death) — the 32 stock `.anim` files ship
   with the model for this reason.

## Rollback

Delete `~/Games/wotlk-clean/Data/patch-Y.MPQ` and restart the client. Nothing else changes: no DBC,
no server data, no addon.

## Remaining work

See [LEDGER.md](LEDGER.md) for the rest of the boss list, the other models with the same conversion
defect, and the rescan procedure.
