# White boss models — ledger

One row per batch. Batch 1 is built and installed; everything below it is open.

## Batch 1 — goblin male (done)

[`dist/patch-Y.MPQ`](dist/patch-Y.MPQ) restores the stock `Character\Goblin\Male\GoblinMale.m2` over
the broken Ascension HD conversion. Root cause and evidence: [README.md](README.md).

| Creature | Boss | Display | Model | State |
|---|---|---|---|---|
| 643 | Sneed | 7125 | 831 | fixed by patch-Y |
| 647 | Captain Greenskin | 7113 | 831 | fixed by patch-Y |
| 1763 | Gilnid | 7124 | 831 | fixed by patch-Y |
| 9543 | Ribbly Screwspigot | 8667 | 831 | fixed by patch-Y |
| 13601 | Tinkerer Gizlock | 7125 | 831 | fixed by patch-Y |

Also fixes every other goblin male NPC, because the model is shared. All five are the same root
cause (`patch-A`'s `GoblinMale.m2` + `GoblinMale00.skin`), so they ship together.

## How this batch was found

1. `instance_encounters` gives the Journal boss creature entries.
2. `creature_template_model` gives each creature's display id.
3. `CreatureDisplayInfo.dbc` gives the model id and the extended display id.
4. `CreatureModelData.dbc` gives the model path; the client loads `.m2`, the DBC stores `.mdx`.
5. `CreatureDisplayInfoExtra.dbc` gives the baked NPC texture name.
6. StormLib `SFileHasFile` checks every archive for the model, its skins and the baked texture.
7. The model itself is audited: parse the M2 texture table and the `.skin` batches, resolve each
   batch to its texture entry, and sum the vertices per entry and per texture type.

The defect signature is **which texture entry the body uses**, not a missing-entry count: the
goblin's body sits on the hair slot (type 6, 61.9%) and cape slot (type 2, 3.8%), while the skin slot
(type 1) that receives the baked NPC texture covers only 34.1%.

An earlier version of this ledger used a different metric ("share on the skin slot", with a claimed
95%+ for working models). That metric does not reproduce and is withdrawn. Control numbers from the
review, all on the corrected metric (top entry shares):

| Model | Shares |
|---|---|
| HD HumanMale | 46.1% / 46.6% / 5.0% |
| HD OrcMale | 39.5% / 45.3% / 3.3% |
| Stock HumanMale | 54.7% / 39.9% / 5.3% |

The shares alone do not separate working from broken models. The call for the goblin rests on its
entry→type mapping plus the in-game white render, and every future candidate needs the same in-game
confirmation before it joins a patch.

## Open — same defect class, needs an in-game check first

- `Character\Goblin\Female\GoblinFemale.M2`: 60.1% of vertices on texture type 6, all 15,390
  vertices batched. Female goblins are not Journal bosses; needs an in-game white/garbled
  confirmation before it joins a patch.
- `Character\HighElf\Male\BloodElfMale.m2`: 27.5% skin / 4.6% cape. HighElf is a custom race; no
  Journal boss uses it.
- `Character\Naga_\Male\naga_male.m2`: 43.6% skin, and `ArmorReflect4.blp` (entry 1) has 0
  referenced vertices. Likely fine; do not treat it as a defect without an in-game report.

If a candidate is confirmed, add its stock file set from `common-2.MPQ`: the model, its skins
(equal to the model's own skin count) and its external `.anim` files.

## Open — not scanned yet

- **Journal rares.** The scan covered `instance_encounters` only. Rares are ordinary `creature` spawns
  inside instance maps; scan them the same way before the next batch.
- **Sixteen encounter rows name no creature template** in the base world DB (for example 58630
  Mal'ganis, 72706 Valithria Dreamwalker, 72959 Gunship Battle). They resolve to no display, so they
  are a separate missing-model case, not white models.
- **Non-character models.** Reforged `Creature\…` models from `patch-B…patch-U` were not audited for
  the same texture-entry defect. The boss scan found no missing model files and no missing baked
  textures, so a white boss there needs the model audit, not the presence check.
- **Collections previews.** Mounts, pets and toys use `model:SetCreature` too. Out of scope here.

## Client-patch contract

`specs/client-patch.md` and `tools/client-patch/` are merged on `local-server-setup`. This patch
already uses the agreed layout (`build.py`, `dist/patch-Y.MPQ`, `manifest.json`), the schema 1
manifest fields, and passes the verifier:

```text
$ python3 tools/client-patch/client_patch.py verify dist/patch-Y.MPQ --manifest manifest.json
dist/patch-Y.MPQ: 36 files, ok
```

Recorded exception: `build.py` writes the manifest itself instead of importing `tools/client-patch/`.
Switching it to `client_patch.py manifest` and removing the duplicate writer is a follow-up.
`data/client-patches/README.md` carries this patch's index row.

## Rules for the next batch

- Add a model only when it is the same root cause (broken replacement conversion) **and** the patch
  stays small. Otherwise write a separate patch; keep one owner per patch letter.
- `patch-Z.MPQ` belongs to the map/POI branch and loads after `patch-Y`. If a `patch-Z` entry ever
  collides with a path in this patch, record the collision here and stop; do not merge silently.
- Rebuild with `python3 build.py`; pin the new source hashes in the script and regenerate
  `manifest.json`. `build.py --check` and `client_patch.py verify` must both pass before the archive
  leaves this directory.
