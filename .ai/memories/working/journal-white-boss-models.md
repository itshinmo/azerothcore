---
description: Journal dungeon/raid card previews render white/untextured for some bosses (e.g. Gilnid)
owner: implementer + server-operator
status: fix built and installed, in-game pass pending
related: local-server-setup
created: 2026-11-21
---

# White boss models in the journal

## Context

Owner reported journal preview models rendering white for some bosses. Previews are client-side
(`model:SetCreature(entry)` through the client's creature cache); the server feeds only records.
The client is the WoWSilicon Ascension bundle: patch-A carries the Ascension model pack and glue
screens; patch-S was deleted (Orgrimmar performance).

## Root cause (confirmed, re-measured in review)

The Ascension pack replaces `Character\Goblin\Male\GoblinMale.m2` with a converted HD model whose
texture mapping is wrong. Vertex share per texture entry in `GoblinMale00.skin`: 9,236 (61.9%) on
the character hair slot (entry 1, type 6), 5,095 (34.1%) on the skin slot (entry 0, type 1), 564
(3.8%) on the cape slot (entry 3, type 2), 26 on a doodad texture and 8 on the eye glow. All 14,929
vertices are batched. The baked NPC texture fills only the type-1 slot, so the 61.9% on the hair
slot and the cape share render white.

An earlier hypothesis blamed a missing cape texture and a 572-vertex unassigned group. Both were
measurement errors; there is no unassigned group.

`dist/patch-Y.MPQ` in `data/client-patches/white-boss-models/` overlays the stock model, three skins
and the 32 external animations from `common-2.MPQ`. It fixes Gilnid plus Sneed, Captain Greenskin,
Ribbly Screwspigot and Tinkerer Gizlock, and every other goblin male NPC. The owner's installed copy
has the build hash `b236c1c3…`; details, manifest and test steps: that directory's `README.md`,
remaining batches: `LEDGER.md`.

## Findings

- Replacement-model defect, not a missing texture, not a display-id problem, and not a journal bug:
  the world creature uses the same model and is white too.
- A display-id pin would change the look; the model overlay restores the actual boss model, so the
  pin list stays a fallback for a case with no usable stock model (none found among Journal bosses).
- Open: female goblin (60.1% on type 6), custom HighElf male (27.5% skin / 4.6% cape) and naga male
  (43.6% skin, `ArmorReflect4.blp` unused) share weaker versions of the metric; none is a Journal
  boss, so they wait for an in-game check.
- Sixteen encounter rows name no creature template in the base world DB; they have no display, so
  they are a separate missing-model case.

## To promote on resolution

- Client-patch pipeline: `specs/content-pipeline.md` and the unmerged `specs/client-patch.md`.
- If display-id pinning ever wins for some model: the pin list lives with the journal module's data.
