# Race/class combos — creation DBC patch (`patch-V.MPQ`)

Status: proposal artifact. Built and verified; **not installed** on the live client. The pair list is
not owner-approved; see [RFC-007](../../../rfcs/active/RFC-007-race-class-combos.md) and
[OPEN-QUESTIONS](../../../decisions/OPEN-QUESTIONS.md).

This patch carries two whole-file character-creation DBCs:

| File | Source | Source rows | Output rows | Output size |
|------|--------|-------------|-------------|-------------|
| `DBFilesClient\CharBaseInfo.dbc` | `Data/enUS/locale-enUS.MPQ` | 62 | 67 | 155 bytes |
| `DBFilesClient\CharStartOutfit.dbc` | `Data/enUS/patch-enUS-2.MPQ` | 126 | 134 | 39,685 bytes |

`CharBaseInfo` adds `(2,8)`, `(3,8)`, `(7,5)`, `(8,9)`, `(10,1)`. The source is Ascension-modified:
stock WotLK has 61 rows, and the effective file has 62 because it already contains `(8,8)` Troll
Mage. `CharStartOutfit` adds IDs `950400-950407`, copied from the same-class source rows (including
the display and inventory-slot arrays) for the four pairs without an existing row; Dwarf Mage already
exists.

## Record size (important)

`CharStartOutfit.dbc` is **296 bytes per row**, not 308:

- header: 126 rows, 77 declared fields, `record_size = 296`, string block 1;
- physical layout: `d` 4 + `bbb` 3 + `X` 1 + 24 items × 4 + 48 display/slot × 4 = **296**;
- `DBCFileLoader` treats `b` and `X` as one byte and `x` as four; `d` is the sort field;
- 20 + 126 × 296 + 1 = 37,317 bytes; 20 + 134 × 296 + 1 = 39,685 bytes.

A 308-byte stride would misalign every row. `build.py` asserts the physical 296-byte layout and the
header's `record_size` before packing. Do not use `field_count * 4` for this table.

## Sources and hashes

| Archive | SHA256 |
|---------|--------|
| `Data/enUS/locale-enUS.MPQ` | `45f02a3bf3964b169f397cea58113cdce5fa7bdf58d4b63f68e46255bb3bd3ea` |
| `Data/enUS/patch-enUS-2.MPQ` | `ab9af8457f0d7b99a562f26b7d1651bbf68ebc37ddb249d01ac860ccc8746ff4` |

- `CharBaseInfo.dbc` source: `1e81c6f8a218b187187c9f13e65cad39920aab56a57f2955d72385d94fee2e25`
  output: `23dbf975092271ca511eb6378c30697e6f2fec1ccf195ab9680977f8a43fa505`
- `CharStartOutfit.dbc` source: `a026407cd4fa60867ac2eda1070e89679e811774b476980902125f6d5af61540`
  output: `03ab1105f505293bb89204c5a5fc88a49527c06c1eab2bddf34b979ca7d3ee52`

Artifact: `dist/patch-V.MPQ`, 6,099 bytes, SHA256
`50e4477b93678272ad35089bfbbd6c8fa7f884c98d1d3171491b29da49d4731c`.

## Build and verify

```bash
python3 data/client-patches/race-class-combos/build.py --client-data ~/Games/wotlk-clean/Data
python3 data/client-patches/race-class-combos/build.py --check
```

The builder pins both source archives and DBCs, rewrites the whole tables, packs MPQ v1 with zlib,
fixed file times, listfile and attributes, then extracts both entries back and compares hashes.
`--check` compares the archive and entries with `manifest.json`.

With the client-patch tool from `feat/map-poi`:

```bash
python3 tools/client-patch/client_patch.py verify \
    data/client-patches/race-class-combos/dist/patch-V.MPQ \
    --manifest data/client-patches/race-class-combos/manifest.json
```

Binary proof (this branch has `* text eol=lf`; the rules in `.gitattributes` keep the archive out):

```text
git hash-object --path=data/client-patches/race-class-combos/dist/patch-V.MPQ \
    data/client-patches/race-class-combos/dist/patch-V.MPQ
# d6c466f9ea2909a368b93899b967b975e632cf1d
git hash-object --no-filters \
    data/client-patches/race-class-combos/dist/patch-V.MPQ
# d6c466f9ea2909a368b93899b967b975e632cf1d
sha256 = 50e4477b93678272ad35089bfbbd6c8fa7f884c98d1d3171491b29da49d4731c
```

## Install and test

1. Copy `dist/patch-V.MPQ` to a **scratch** client `Data/` directory. Do not write the live client.
2. Clear the client `Cache`.
3. Run `client_patch.py which` and confirm `patch-V` wins both `DBFilesClient\CharBaseInfo.dbc` and
   `DBFilesClient\CharStartOutfit.dbc`. If `patch-X`, `patch-Y`, `patch-Z`, a Reforged archive, or a
   locale patch wins, stop; do not ship two carriers.
4. Confirm the creation screen shows the new class buttons and the class-appropriate preview gear.
5. Apply the matching server SQL and `DataDir/dbc/CharStartOutfit.dbc` on a local/test realm; create
   each pair, spawn, check outfit/actions/spells/trainer.
6. Revert by deleting `patch-V.MPQ` and restoring `DataDir/dbc/CharStartOutfit.dbc`.

## Load order

`patch-V` is a base alphabetic patch: it loads after `patch-U` and before `patch-X/Y/Z` on the English
client. `patch-X` carries only `Item.dbc`; `patch-Y` carries goblin models; neither carries these
DBCs. `patch-Z` is not installed. The client-patch family is defined by ADR-027 on the unmerged
`feat/map-poi` branch; `patch-V` is a character-creation DBC carrier proposed by this artifact and
needs the client-patch owner's approval.

## Merge reconciliation

This branch predates `local-server-setup`'s `data/client-patches/README.md` contract. Do not replace
that file. On merge:

- add the ledger row below to `data/client-patches/README.md`;
- keep the schema 1 manifest and the `.gitattributes` binary rules;
- if the contract assigns character-creation DBCs a different archive letter, rename `patch-V` in
  the ledger, manifest, README, and RFC together; never ship two carriers;
- `build.py` writes the manifest itself because `tools/client-patch/` is not in this branch; switch
  to the pipeline tool when it merges.

## Ledger row

```text
- [race-class-combos](race-class-combos/README.md) — `race-class-combos/dist/patch-V.MPQ`:
  character-creation DBCs for the proposed extended race/class pairs. `CharBaseInfo.dbc` 62 -> 67
  rows, `CharStartOutfit.dbc` 126 -> 134 rows; 2 DBCs; SHA256
  50e4477b93678272ad35089bfbbd6c8fa7f884c98d1d3171491b29da49d4731c.
```

## License

The DBCs come from the owner's licensed 3.3.5a client install. No Ascension or Reforged custom model,
texture, form, mount, or totem is packed. The patch is data-only; it contains no executable content.
