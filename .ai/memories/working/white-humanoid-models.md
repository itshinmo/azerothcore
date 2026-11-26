---
description: Journal boss previews render player-model NPCs white; the 3.3.5 pane never dresses an extended display, the client hook is built and proven, and the dressing code is not written
owner: implementer
status: diagnosis complete and client hook proven; dressing code not written; parked
related: local-server-setup, journal-white-boss-models.md
created: 2026-11-24
updated: 2026-11-26
---

# White humanoid NPC models in the Journal

## Symptom

Journal dungeon/raid previews draw humanoid bosses as flat white. The world draws the same NPCs
correctly. The owner's list covers RFK, Deadmines, Wailing Caverns, Shadowfang Keep, Blackfathom
Deeps, Stormwind Stockade, Scarlet Monastery, Uldaman, Maraudon, Zul'Farrak and Sunken Temple.

## Root cause

The preview is drawn with `PlayerModel:SetCreature(entry)`. In this client the pane resolves the
creature, stores its GUID on the model object at `+0x368`, and returns without running the character
compositor that a spawned unit gets. The type-1 skin slot is therefore never filled with the extended
display's baked texture and the naked body draws white.

Evidence:

- A bare `PlayerModel:SetCreature(639)` frame outside the Journal is equally white.
- Hamhock (Stockade) is the only boss there with a **plain** display and draws correctly. Plain
  displays carry named textures inside the model and need no compositor.
- 14,048 of 29,947 creature display rows (47%) are extended displays and affected.
- An in-world test with a grid texture at VanCleef's bake path turned him solid green, proving the
  bake file, the path and the DBC rows are correct. Only the preview path fails.
- A five-target probe of the client (2026-11-26) shows both `0x5977e0` (SetCreature, 11 hits) and
  `0x597700` (display build, 9 hits) on the preview path, while `0x5975e0` (record resolution),
  `0x597840` (set display id) and `0x84f280` (model setter) stay at zero. The display builder runs,
  so the break is inside it: it builds the model from the display record but never binds the
  extended display's bake to the skin slot.

Ruled out: missing bakes (every reported boss's bake exists in the winning archive), wrong display
ids, missing models, and a Journal addon bug. The earlier "HD model moved vertices to texture type 8"
theory is withdrawn: the pane supplies no texture to any slot, so slot layout cannot be the cause.

## Client hook

[ADR-036](../../../decisions/ADR-036-client-dll-patches.md) (proposed) permits one reviewed
`DivxDecoder.dll` proxy. `tools/client-dll/white-model-hook/` implements it: loader-forwarder exports,
structurally guarded detours with per-target byte lengths, and a probe build that only counts.

The display builder runs, so the fix cannot be "re-enable a call". It must be **added**: inside the
build, take the display record's extended display, load that bake onto the model object's skin slot
and set the geosets it covers, mirroring `CGUnit_C::UpdateCharacterCustomization`.

Client facts for that work: image base `0x400000`; pane setter `0x5977e0`; display builder `0x597700`;
record handler `0x5975e0`; display-id setter `0x597840`; model setter `0x84f280`.

## Rejected fixes

- **Restore stock race models.** Changes the player's own character; a stock goblin model is still
  white in the pane, so it does not fix the symptom.
- **Remap the M2 texture slots.** The pane supplies no texture to any slot.
- **One model clone per boss.** 5-15 MB each, 153 bosses, 1-1.5 GB. Measured and rejected.
- **Portraits.** Loses the interactive 3D preview the owner requires.
- **Spawn a preview unit.** Side effects in cities and instances.

## Next session

1. Attach a debugger and instrument `0x597700` to dump the display record it receives and the model
   object's texture-slot fields.
2. Identify how the client reads `CreatureDisplayInfoExtra` and its bake name.
3. Locate the model object's texture-slot and geoset setters.
4. Call the compositor from inside the detour.
5. Verify one boss per race and gender, in and out of the Journal.

A debugger is required for this; rapid rebuild-and-test cycles cost more than they reveal.

## Evidence

- Effective DBCs: `CreatureDisplayInfo`/`CreatureModelData` from `patch-C.mpq`,
  `CreatureDisplayInfoExtra` from `patch-A.MPQ`.
- World render proven with a grid bake at
  `Textures\BakedNPCTextures\CreatureDisplayExtra-00641_HD.blp`.
- Probe run 2026-11-26: `0x5977e0 = 11`, `0x597700 = 9`, all other targets `0`.
