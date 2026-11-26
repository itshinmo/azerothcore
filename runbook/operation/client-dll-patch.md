# Client DLL patch — runbook

Procedure for building, installing and rolling back the `DivxDecoder.dll` proxy. Contract:
[ADR-036](../../decisions/ADR-036-client-dll-patches.md) (proposed). Test plan:
[tools/client-dll/white-model-hook/TEST-PLAN.md](../../tools/client-dll/white-model-hook/TEST-PLAN.md).

Agents never install into the live client. The owner installs and tests.

## When to use

Only for the pane-model defect named in ADR-036. No other executable artifact is permitted without
its own ADR.

## Prerequisites

- `brew install mingw-w64` (i686 cross toolchain).
- The supported client, closed.
- The exe the build targets. `check_anchor.py` reads it and prints its SHA256, which is the build's
  expected baseline.

## Build

```bash
cd tools/client-dll/white-model-hook
sh build.sh                      # forwarding only
DETOUR=1 sh build.sh             # with probes
python3 verify.py dist/DivxDecoder.dll
python3 check_anchor.py [path/to/Wow.exe]
shasum -a 256 dist/DivxDecoder.dll
```

Record the build id and hash in the install note. `dist/` is gitignored; the DLL is never committed.

## Install (owner)

Client closed.

```bash
cd ~/Games/wotlk-clean
mv DivxDecoder.dll DivxDecoder_orig.dll
cp <repo>/tools/client-dll/white-model-hook/dist/DivxDecoder.dll .
```

The name is `DivxDecoder_orig.dll` with an underscore: the export table forwards to that exact name.

Keep a second copy of the original under a distinct name if you want a belt-and-braces rollback.

## Verify

Start the client and read `white-model-hook.log` in the game directory.

- `forwarding only; probes not built in` and the client reaches the world: forwarding works.
- `... patched` per target, then count lines that change only when a counter changes: probes work.
- `SKIPPED` means a guard refused: the exe is not the pinned baseline, or a target moved. Do not
  force it; rebuild the target list for that client.

## Rollback

```bash
cd ~/Games/wotlk-clean
rm DivxDecoder.dll
mv DivxDecoder_orig.dll DivxDecoder.dll
rm -f white-model-hook.log
```

No MPQ, DBC, or server change is involved.

## Failure modes

| Symptom | Cause | Action |
|---|---|---|
| Client will not start, no log | Forwarders unresolved | `DivxDecoder_orig.dll` missing or misnamed |
| Client will not start, log shows the build then stops | A stub faulted | Roll back; report the build id and the last log line |
| Client starts, targets `SKIPPED` | Wrong exe baseline or moved functions | Rebuild the target list against that exe |
| Log never appears | DLL not loaded | Confirm the file is beside `Wow.exe`, not in `Data/` |
| Client hangs at load | A build with a broken stub | Roll back, re-run the offline checks; a shim rewritten into a self-jump did this once |

## Hard rules

- Never test a build that has not passed `verify.py` and `check_anchor.py`.
- Never install a DLL you did not just build, and always match the hash in the install note.
- Never `FreeLibrary` while a detour is installed.
- Relocations stay enabled so the loader can never reject the image.
- One executable artifact, one ADR.
