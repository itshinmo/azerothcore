# ADR-036 — Client DLL patches: a reviewed proxy DLL for model-frame fixes

- Status: proposed
- Date: 2026-11-26
- Amends the "no exe or DLL content" rule of [ADR-027](ADR-027-client-patch-pipeline.md) for the
  single case below. Everything else in ADR-027 stands.

## Context

ADR-027 confines client patches to MPQ archives: data and Lua/XML only, never executable content.
That rule produced three working patches (`patch-X` Item.dbc, `patch-Y` models, `patch-Z` map/UI) and
kept the client trivially replaceable.

It also blocks a defect we cannot fix with data. The 3.3.5 client's `PlayerModel` pane resolves a
creature and stores its GUID, but never runs the character-compositor dressing step that a spawned
unit gets. For a `CreatureDisplayInfoExtra` NPC the body samples the type-1 skin slot, which only the
extended display's baked texture fills, so the preview draws flat white. The world path is unaffected.

Measured scope: 14,048 of 29,947 creature display rows (47%) are extended displays. The Journal shows
a live 3D preview of every instance boss; 153 of those resolve through an extended display.

Every data-only alternative was measured and rejected:

| Alternative | Result |
|---|---|
| Restore stock race models | Players' own characters change; a stock goblin model is still white in the pane, so it does not fix the symptom either |
| Rewrite the M2 texture-slot types | The pane supplies no texture to any slot, so the slot layout is irrelevant |
| One model clone per boss | 5-15 MB per model, 153 clones, 1-1.5 GB. Rejected |
| Pre-rendered portraits | 2D; the owner requires interactive 3D |
| Spawn a preview unit per boss | Side effects in cities and instances |

Instrumentation of the live client (2026-11-26) established that `SetCreature` is called and the
display-resolution chain is then never entered. There is no disabled call to re-enable: the dressing
step has to be added.

The client already loads code we did not ship: stock `Wow.exe` imports four functions from
`DivxDecoder.dll`, and the macOS/WoWSilicon stack loads `mods/libSiliconPatch.dll`.

## Decision

1. **Client DLL patches are allowed as a narrow, reviewed exception.** MPQ-only remains the default
   for all data and UI work. An executable patch needs its own ADR naming its exact behavior and a
   written test plan; this ADR authorizes exactly one, for the pane-model defect. The test plan is
   [tools/client-dll/white-model-hook/TEST-PLAN.md](../tools/client-dll/white-model-hook/TEST-PLAN.md)
   and the procedure is [runbook/operation/client-dll-patch.md](../runbook/operation/client-dll-patch.md).
2. **Shipping vector: a `DivxDecoder.dll` proxy.** Stock `Wow.exe` imports `InitializeDivxDecoder`,
   `UnInitializeDivxDecoder`, `DivxDecode` and `SetOutputFormat` from that file, so the Windows loader
   loads our DLL for every player whose copy sits beside the exe. The four exports are **loader
   forwarders** to a renamed original, `DivxDecoder_orig.dll`: the loader resolves them before any
   game code runs, so the video path can never hold a null pointer.
3. **No on-disk edit of the game executable.** One in-memory code patch per targeted function: a
   9-byte or 14-byte `jmp` written by the DLL at load, into a stub in the DLL that replays the
   displaced instructions and jumps back.
4. **Scope of behavior.** The only permitted change is making a `PlayerModel` pane apply an
   extended display's baked texture. No UI, input, network, file, or account behavior.
5. **Fixed addresses with structural guards, not signatures.** Targets are fixed virtual addresses
   for one pinned exe build. The DLL patches only when the image base is `0x400000`, every target
   lies in a committed readable region, and every prologue matches its expected bytes. Any mismatch
   skips that target and logs it. This is a guard against the wrong build, not a general signature
   match: pairing a different image based at `0x400000` whose generic prologues happen to match is
   not detectable here, so the launcher must pin the executable hash (clause 7).
6. **Fail safe, not fail loud.** A skipped target leaves the client running unmodified. Faults inside
   a stub cannot be resumed safely, so there is no in-process recovery handler; the mitigation is
   that a stub is 22-27 bytes (the copied prologue plus one indirect jump), verified offline before shipping.
7. **Version pinning and the launcher contract.** The launcher verifies the client `Wow.exe` hash and
   the original DLL hashes, then installs the proxy and its manifest entry. An unknown build gets no
   proxy. Rollback is deleting one file; the launcher keeps the previous copy.
8. **Provenance and review.** Source is tracked. The build is reproducible from any checkout path:
   the toolchain is pinned, the PE timestamp is fixed (`--no-insert-timestamp`), the image base is
   fixed (`--image-base,0x10000000`) because mingw otherwise derives it from the output path, and the
   build id is fixed. The output hash is recorded in the client-patch ledger. No binary without matching source. Prior art credited in the
   source header and README.
9. **Audit and safety.** At most one line per build at load, one line per probe/target at install,
   and a count line only when a counter changes. No per-frame output, no player data. The DLL never
   touches network, files other than its own log, or the account.
10. **Never unloaded.** Relocations are kept, so the image is not tied to a preferred base. The DLL is
    a static import, it loads before the game starts its own threads, and it must not be freed while
    a detour is installed: the `jmp`s would point into unmapped memory.

## Alternatives considered

- **Patch `Wow.exe` on disk.** Every client update invalidates it, the launcher modifies a
  copyrighted executable, and anti-cheat and distribution concerns are worse. Rejected.
- **Inject from the launcher at process start.** Players who launch the exe directly get no fix, and
  the launcher becomes mandatory. Rejected.
- **Require WoWSilicon for all players.** Contradicts the production target (stock Windows). Rejected.
- **Rewrite the pane model code in Lua.** The pane API has no display-info entry point on this build
  (`SetDisplayInfo` and `GetDisplayInfo` are nil). Rejected.
- **Accept white previews.** The owner requires interactive 3D previews. Rejected.
- **Model clones.** Measured at 1-1.5 GB. Rejected.

## Consequences and tradeoffs

- Positive: the Journal can gain correct 3D previews for extended-display bosses with no per-boss
  data and no client-size growth.
- Positive: the mechanism (proxy, forwarders, verified detours) is reusable for future rendering
  defects the data layer cannot express.
- Cost: the project ships executable code. That raises the review bar, requires a pinned toolchain,
  and makes a client build update a maintenance event.
- Risk: a wrong detour crashes at model load rather than at startup. Mitigated by structural guards,
  a fixed-baseline exe, and offline verification that each prologue matches the image and that the assembled stub replays those bytes exactly.
- Risk: a future client update moves the functions. The guards turn that into skipped targets plus
  one log line, not a wrong patch.
- Risk: shipping a proxy DLL next to a commercial executable is legally ordinary but visible. It
  carries only project-authored code and forwards to the file the player already owns.
- Rollback: delete the proxy and restore the renamed original. No MPQ, DBC, or server change.

## Open questions

- Which executable hashes must be supported at launch (retail 3.3.5a builds, plus the Ascension-patched
  build), and how the launcher reports an unsupported build.
- Whether the launcher ships the proxy to players already running WoWSilicon, or detects and skips.

## References

- [ADR-027](ADR-027-client-patch-pipeline.md) — the MPQ-only rule this ADR narrows
- [ADR-032](ADR-032-map-poi-layer.md) — current map/UI patch
- [specs/client-patch.md](../specs/client-patch.md)
- [.ai/memories/working/white-humanoid-models.md](../.ai/memories/working/white-humanoid-models.md)
- ClassicAPI, backport of 4.3.4 `PlayerModel`/`DressUpModel` methods (`SetUpModel` dressing step)
