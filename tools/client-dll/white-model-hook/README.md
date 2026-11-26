# White-model hook — client DLL

Status: **parked after the probe.** The hook mechanism is proven; the dressing step is not written.
Findings: [`.ai/memories/working/white-humanoid-models.md`](../../../.ai/memories/working/white-humanoid-models.md).
Policy: [ADR-036](../../../decisions/ADR-036-client-dll-patches.md) (proposed).

## What is proven

| Claim | Evidence |
|---|---|
| A `DivxDecoder.dll` proxy loads on this client | one full session on the probe build |
| The four Divx exports forward correctly | they are loader forwarders in `DivxDecoder.def`; the client logs in and runs |
| Detours install and survive a session | five targets patched, no crash |
| A mismatched target is skipped, not applied | `patch_one` checks base, mapping, prologue bytes and rel32 range |
| The Journal calls `SetCreature` | probe counter reached 11 on the preview path |

Not proven: per-frame cost. Five `lock incl` counters sit on model-build paths, which are not
per-frame, but nobody has measured them. Fine for a probe; the shipping build must count only once.

## Probe result (2026-11-26)

```
0x5975e0 record->display = 0
0x597700 display build   = 9     <- builds the model
0x5977e0 SetCreature     = 11    <- pane setter
0x597840 set display id  = 0
0x84f280 model setter    = 0
```

`SetCreature` stores the creature GUID at `model+0x368`, and the display builder at `0x597700`
builds the model from the display record. What never happens is the character-compositor dressing
step, so the extended display's bake never reaches the skin slot. The dressing step must be added.

## Layout

| File | Purpose |
|---|---|
| `dllmain.c` | Logging, probe table, structural guards, patch install |
| `DivxDecoder.def` | The four forwarder exports |
| `hook.S` | One stub per probe, each replaying its target's displaced bytes |
| `build.sh` | `ENABLE_DETOUR=0/1`; pinned timestamp and build id; fails on assembler errors |
| `check_anchor.py` | Verifies every probe prologue against the exe, and that hook.S replays it |
| `verify.py` | Verifies exports are forwarders and only KERNEL32 is imported |
| `pe.py` | Read-only PE helper; takes the exe path from `argv` |

## Build

```bash
brew install mingw-w64
sh build.sh            # forwarding only
DETOUR=1 sh build.sh   # with probes
python3 check_anchor.py /path/to/Wow.exe
python3 verify.py dist/DivxDecoder.dll
```

The build is reproducible: the PE timestamp is pinned with `--no-insert-timestamp`, and the build id
is fixed, so the same sources produce identical bytes.

## Install

Client closed. The forwarders resolve against `DivxDecoder_orig.dll`, with an underscore.

```bash
cd ~/Games/wotlk-clean
mv DivxDecoder.dll DivxDecoder_orig.dll
cp <dist>/DivxDecoder.dll .
```

Rollback: delete the proxy, rename the original back.

## Hard-won rules

1. **Never test a binary you assumed was rebuilt.** The first client crash came from a build whose
   assembler step had failed while the stale DLL was installed. `build.sh` now fails loudly, and the
   log carries a build id.
2. **Never generate hook code at runtime.** The crash address was inside a `VirtualAlloc` page.
3. **Replay every displaced instruction, including flag-setting ones**, and size the window to the
   instruction lengths, not to a round number. `0x597840` needs 14 bytes because its `cmp` is six
   bytes long; a 9-byte window resumed mid-instruction.
4. **Verify the target structurally** (base, mapping, prologue, rel32 range) and skip rather than
   guess.
5. **Divx exports must be loader forwarders**, never `LoadLibrary` at attach: `GetModuleFileNameA` on
   a DLL handle failed under Wine and left the video path with null functions.
6. **Keep relocations.** A non-relocatable image is refused when its preferred base is taken or
   Mandatory ASLR is on, and then the client does not start at all.
7. **Never `FreeLibrary` while a detour is installed.**

## Next session

Decode the creature-cache record behind `model+0x368`, find the model object's texture-slot and
geoset setters, and call the engine compositor from inside the `SetCreature` detour. This needs a
debugger attached to a live client, not rapid rebuild cycles.
