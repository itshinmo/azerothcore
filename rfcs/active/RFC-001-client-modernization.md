# RFC-001 — Client modernization: Reforged + Ascension customization + modern UI

- Status: accepted (implementation gated on the owner's downloads and explicit go)
- Date: 2026-11-20
- Author: agent session (modernization/realm-cleanup-and-features)
- Decisions: made by the owner on 2026-11-20 (see Decision record below)

## Problem

The 3.3.5a client looks and animates like 2010. The owner wants: modern character models and
creation customization, modern spell VFX, and later a modern UI. No client-patch pipeline or
distribution story exists yet (parked since ADR-013 planning; `make client-patch-and-extract` is a
planned, unbuilt skill).

## Proposal

Adopt three maintained community stacks, composing as one supported client bundle:

1. **Project Reforged v1.5.8** (projectreforged.github.io/wotlk) as the visual base: modular MPQ
   patches (A players/NPCs, B/D/E environment set, C creatures, G gear, I interface, P spell
   particles, U upright orcs), St0ny's AIO EXE patcher (mandatory), DXVK 3.1.1 x86 (recommended).
   Client-only; zero server changes.
2. **"Ascension Character Customization"** (Nexus mod 907, ~3 GB, author Ijostrom) as the
   replacement for Reforged Patch-A: base WoD HD player/NPC models + 500+ extra creation options.
   Requires the 8 mod DBCs swapped into the server `DataDir/dbc/` (verified list: BarberShopStyle,
   CharSections, CreatureDisplayInfoExtra, EmotesTextSound server-parsed; CharHairGeosets,
   CharHairTextures, CharacterFacialHairStyles, HelmetGeosetVisData client-only). AC validates no
   appearance IDs at create; barber validates against `BarberShopStyle.dbc` — client/server DBC
   sets must be identical. v6 states compatibility with Reforged 1.5.8 (drop-in Patch-A stand-in).
3. **mod-forever-ui** (Adrestie, GPL-2.0) optional: modern UI addon + optional `Wow.exe` byte patcher
   that lists creation/barber choices by name (re-reads `BarberShopStyle.dbc` client-side, so new
   Ascension options get named automatically).

Distribution: the owner plays with the bundle now (manual install); at launch the shipped client +
launcher carries it (per owner decision: Reforged mandatory at launch). This RFC does not cover the
launcher itself.

Adoption order: download owner-side → owner installs on a clean 3.3.5a test client → verify
(creation, barbershop, spells VFX, gear slotting on WoD skeletons, addon compat) → record the
verified bundle + install order in a client-patch runbook → only then bless for friends.

## Spell animations (findings; Phase A decided for this cycle)

- Legion's new cast anims (`SpellVisualAnim`/`SpellVisualKitEffect`, 7.3.0+) have no 3.3.5
  equivalent; `AnimKit.dbc` does not exist before Cataclysm.
- 3.3.5 CAN do distinct caster animations per spell: `SpellVisualKit.dbc.StartAnimID/AnimID` →
  `AnimationData.dbc`, driven via `SpellVisual.castKit/precastKit/channelKit`; flag `0x40` loops the
  anim for long casts. DBC-only work, hours, WotLK-era anims only.
- *Exact* Legion anims (frost-nova hand move) require M2 animation porting into 19 player models —
  a modeling project with real crash risk. Feasible (Reforged teams do M2 work), not cheap.
- Proposed split: Phase A (DBC-only long-cast/cast-loop distinctiveness now, cheap) — Phase B
  (M2 anim porting, owner decision later).

## Alternatives

- SoloCollectionsPlatform-style native client extension (SC2 protocol + DLL injection): powerful,
  gameplay-divergent, DLL distribution heavy. Rejected for now; revisit only if MPQ/addon route hits
  limits.
- Kraiver HD client: distributed with an accused-malicious second exe — excluded.
- No client work: loses the model/creation/VFX wants.

## Impact

- Server: `DataDir/dbc/` swaps + a client-patch runbook; no core code changes.
- Players: must download a ~multi-GB bundle (launcher matters).
- Risk: client/server DBC divergence = silent barbershop stall / creation hang; MPQ load order rules
  needed; St0ny AIO exe edits × ForeverUIPatcher × WoWSilicon coexistence unverified.

## Open questions

Resolved by the owner on 2026-11-20:

1. ~~Verify bundle on a clean client before blessing — owner downloads; when?~~ → The owner
   downloads the bundle after planning; verification follows as the first implementation step.
2. ~~Diff the 8 DBCs against Reforged's on arrival?~~ → **Skip Reforged Patch-A entirely.** The
   Ascension pack covers players and NPCs and states v1.5.8 parity; nothing is merged. Diffing only
   happens if a visual looks wrong in testing.
3. ~~Phase A spell-animation DBC work: this cycle or defer?~~ → **This cycle** (DBC-only cast-anim
   distinctiveness; M2 porting stays a later owner decision).
4. ~~Does the shipped client bundle also carry mod-forever-ui?~~ → **Yes, include it.** Verified
   compatible with our addon stack: it is one self-contained UI addon plus an exe patch that only
   touches creation/barber naming; it conflicts only with other full-UI-replacement suites
   (DragonUI-class), not with frame-building addons (GM Helper, Transmog, Journal).

## Decision record

Owner decisions, 2026-11-20:

1. Adopt Project Reforged with the Ascension pack **replacing Patch-A** (skip patch-A; no DBC
   merging).
2. Include **mod-forever-ui** (modern UI + named creation/barber choices) in the bundle.
3. Spell animations: Phase A (DBC-only `SpellVisualKit.StartAnimID/AnimID` cast-anim work) happens
   this cycle; exact Legion M2 anim porting is deferred to a later owner decision.
4. Distribution: owner plays with the bundle now; at launch the shipped client + launcher is
   mandatory (Reforged-based client required for players).
5. The owner downloads the bundle files (listed below); the agent never downloads them.

Download bundle (owner-side, verified list):

| File | URL | Size | Purpose |
|------|-----|------|---------|
| Ascension Character Customization v6 (main file) | https://www.nexusmods.com/worldofwarcraft/mods/907 | ~3 GB | WoD HD models + 500+ creation options (replaces Patch-A) |
| Project Reforged patch set (all modules except A) | https://projectreforged.github.io/wotlk/downloads/ | multi-GB | VFX, environment, gear, interface, sounds |
| St0ny's AIO EXE Patcher + Reforged preset | linked from the Reforged downloads page | small | Mandatory exe patches |
| DXVK 3.1.1 x86 (`d3d9.dll` from the release) | https://github.com/doitsujin/dxvk/releases/tag/v3.1.1 | small | Renderer fix |
| mod-forever-ui (release/installer from the repo README) | https://github.com/Adrestie/mod-forever-ui | small | Modern UI + named choices |
| LuxVelum (optional) | linked from the Reforged downloads page | small | Atmospheric fog |

Exe patches target the Windows `Wow.exe` build 12340 under Wine; WoWSilicon reads the MPQ data
patches but not exe patches, so full-bundle testing happens on a Wine client.

<!-- When accepted, fold the durable content into specs/ or decisions/ and move the RFC to archived/. -->
