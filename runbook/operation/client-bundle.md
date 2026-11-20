# Client bundle — the supported play client

The owner plays on the **modernized bundle client**; at launch this becomes the shipped player
client (with a launcher). Verified working on 2026-11-20 with the owner in-game: 120 FPS, all
screens functional. Owner decisions recorded in [RFC-001](../../rfcs/active/RFC-001-client-modernization.md).

## The verified bundle

| Component | Source | State |
|---|---|---|
| `Wow.exe` | WoWSilicon build (SSE2-optimized for Apple Silicon) | active — the fast path; St0ny-patched vanilla exe measured 14 FPS (x87 emulation), reverted |
| d3d9.dll | WoWSilicon's own (installed by its Game Patch) | active — WoWSilicon re-offers the patch whenever its hash check fails; click Patch |
| patch-A.MPQ | "Ascension Character Customization" v6 (Nexus mod 907) | active — WoD HD models + 500+ creation options |
| 8 server DBCs | same mod | active — copied into server `DataDir/dbc/`; worldserver restart applies them |
| patch-B/C/D/E/G/I/M/N/P/S/U.MPQ | Project Reforged v1.5.8 (skip patch-A) | active — VFX, environment, gear, interface, sounds |
| ForeverUI addon + art | mod-forever-ui (Adrestie) | active — in-game modern UI: `Interface/AddOns/ForeverUI` + `Interface/foreverui` art ONLY; its loose `Interface/GlueXML` and `Interface/Minimap` art are NOT installed (they conflict with Ascension's glue — see Screens and glue ownership) |
| GM Helper | `tools/gm-addon/` | active — testing addon |

Paths: client `~/Games/wotlk-clean` (WoWSilicon launcher, realmlist `127.0.0.1`); vanilla reference
exe kept at `~/Downloads/wow-related/Wow-clean.exe` (build-12340, unmodified).

## Screens and glue ownership

The **Ascension patch-A MPQ owns the glue screens** (login, character select, character creation —
its modern creation layout carries the 500+ options). No other mod may redefine those screens:
ForeverUI's loose `Interface/GlueXML` conflicted with them (duplicate widgets, overlapping text,
Lua errors) and was removed. Two mods both shipping GlueXML for the same screens do not compose.

## Proven incompatible or dropped (do not re-add without a new decision)

- **St0ny AIO EXE Patcher (46 patches)**: patches vanilla `Wow.exe` fine, but that exe runs x87
  through software emulation on Apple Silicon → 14 FPS measured; reverted. Its patcher also
  corrupts the exe when run after any foreign byte patch (verified both orders).
- **ForeverUIPatcher (named creation choices)**: needs vanilla-byte offsets; incompatible with
  St0ny in either order (verified; the merged exe failed St0ny's own integrity scan). Creation and
  barber choices show numbers instead of names.
- **ForeverUI loose GlueXML + Minimap art**: conflicts with Ascension's glue (above).
- **LuxVelum**: needs St0ny's loader hook; inert on the WoWSilicon exe. Removed.
- **DXVK 3.1.1**: blocked by WoWSilicon's Game Patch gate (it re-installs its own d3d9). Removed;
  a DXVK version matters little for the bundle's look.

## Install order (for rebuilding a client copy from scratch)

1. Copy a clean 3.3.5a build 12340 client (vanilla `Wow.exe`, stock `Data/`).
2. Launch it once through WoWSilicon; apply its CrossOver and Game patches (its d3d9).
3. Copy the 12 custom MPQs into `Data/`: Ascension `patch-A.MPQ` + Reforged
   `patch-B/C/D/E/G/I/M/N/P/S/U.MPQ` (never Reforged patch-A).
4. Copy the mod's 8 DBCs into the **server** `DataDir/dbc/` and restart the worldserver.
5. Install addons into `Interface/AddOns/`: the ForeverUI addon folder and `Interface/foreverui`
   art ONLY — never its `GlueXML` or `Minimap` art (conflicts with Ascension's glue), plus GM Helper.
6. Point `Data/enUS/realmlist.wtf` at the realm; play.

## Verification checklist (per client rebuild)

- Client starts; no addon dependency errors.
- Creation screen: modern layout, 500+ options cycle, HD models; no Lua errors (glue dialogs).
- Login/character select render cleanly; no overlapping widgets.
- In-world: HD models and gear, Reforged spell VFX, GM Helper tabs, FPS in the expected range.

## References

- [RFC-001](../../rfcs/active/RFC-001-client-modernization.md)
- [ADR-018](../../decisions/ADR-018-realm-strategy.md) (realm layout)
- [environment-overview.md](../development/environment-overview.md)
