# Race/class combos — ledger

One row per batch. This batch is a proposal artifact, not installed.

## Batch 1 (proposed, not owner-approved)

[`dist/patch-V.MPQ`](dist/patch-V.MPQ) adds the creation data for the five recommended pairs:
Dwarf Mage, Orc Mage, Gnome Priest, Troll Warlock, Blood Elf Warrior. See
[RFC-007](../../../rfcs/active/RFC-007-race-class-combos.md) for the evidence and the open owner
decisions.

| Pair | RaceID | ClassID | CharBaseInfo | CharStartOutfit |
|------|--------|---------|--------------|-----------------|
| Dwarf Mage | 3 | 8 | added | existing rows 35/52 |
| Orc Mage | 2 | 8 | added | added 950400/950401 |
| Gnome Priest | 7 | 5 | added | added 950402/950403 |
| Troll Warlock | 8 | 9 | added | added 950404/950405 |
| Blood Elf Warrior | 10 | 1 | added | added 950406/950407 |

Not in batch 1: Troll Druid (no Troll form models), Undead/Tauren Paladin (no class mount wiring or
quests), Dwarf Shaman (no totem quest chain), Human/Undead Hunter (no Taming the Beast quest row).

## Artifact

- `dist/patch-V.MPQ`: 2 files, 6,099 bytes, SHA256
  `50e4477b93678272ad35089bfbbd6c8fa7f884c98d1d3171491b29da49d4731c`;
- `CharBaseInfo.dbc`: 62 effective rows -> 67, 155 bytes;
- `CharStartOutfit.dbc`: 126 effective rows -> 134, 296-byte rows, 39,685 bytes.

## Open

- Owner approval of the target list and batch.
- Client-patch owner approval of `patch-V` as the character-creation DBC carrier.
- In-client creation-preview check; the engine call is opaque, so the eight outfit rows ship in the
  client patch and are tested.
- Server `DataDir/dbc/CharStartOutfit.dbc` deployment must use the same 134-row bytes; no SQL rows
  for outfits.
- Merge `data/client-patches/README.md` with the `local-server-setup` contract; do not replace it.

## Contract

`specs/client-patch.md`, `tools/client-patch/`, and ADR-027 are merged on `local-server-setup`.
This directory uses the agreed layout (`build.py`, `dist/patch-V.MPQ`, `manifest.json`, README) and
schema 1 manifest fields. `build.py` still writes the manifest itself; switch to
`client_patch.py manifest` in a follow-up.
