# White-model hook — test plan

Contract: [ADR-036](../../../decisions/ADR-036-client-dll-patches.md) (proposed).
Tool: `tools/client-dll/white-model-hook/`.

## Test levels

| Level | What runs | Gate |
|---|---|---|
| Offline | `check_anchor.py`, `verify.py`, reproducible-hash check | Every build, before install |
| Forwarding | Install, log in, reach the world | Once per client family |
| Probe | Install probe build, exercise the Journal, read the log | Once per target set |
| Behaviour | The actual dressing fix | Not built yet |

## Offline checks (no client)

```bash
sh build.sh && python3 verify.py dist/DivxDecoder.dll
DETOUR=1 sh build.sh && python3 check_anchor.py
```

Pass criteria:

1. `verify.py` reports all four exports as forwarders to `DivxDecoder_orig.*` and KERNEL32 as the only
   import.
2. `check_anchor.py` reports, for each of the five targets: prologue matches the image, the window
   length is a listed instruction boundary, and the assembled stub replays those bytes byte for byte.
3. Two builds in different directories produce the same SHA256.

Any failure stops the install. There is no "try it in the client and see".

## Forwarding test

Client closed.

```bash
cd ~/Games/wotlk-clean
mv DivxDecoder.dll DivxDecoder_orig.dll
cp <dist>/DivxDecoder.dll .
```

Expected log:

```
white-model-hook: build <id>
white-model-hook: forwarding only; probes not built in
```

Expected in game: the client reaches character select and the world. **This is the only pass criterion.**
If the client does not start, forwarding is broken: roll back and re-run the offline checks.

Rollback: delete the proxy, rename `DivxDecoder_orig.dll` back to `DivxDecoder.dll`.

## Probe test

Same install with the `DETOUR=1` build. Expected log, one line per target then count lines:

```
white-model-hook: build <id>
white-model-hook: 0x5975e0 record->display patched
...
white-model-hook: 0x5977e0 SetCreature      = 11
```

Pass criteria:

1. Every target line says `patched`, or a `SKIPPED` line explains which guard refused.
2. Opening the Journal on a player-model boss increments at least one counter.
3. The client shows no crash and no new Lua error.
4. The log does not grow when nothing changes: count lines appear only on a change.

## Behaviour test (not yet available)

When the dressing code exists, per race and gender:

1. Open a boss that uses an extended display; confirm the body, armour, hair and face are textured.
2. Confirm the same NPC in the world is unchanged.
3. Confirm a plain-display boss is unchanged.
4. Confirm the player's own character and the character-creation screen are unchanged.
5. Confirm no weapon appears in the preview (expected: the server sends NPC weapons only for spawned
   units).

## Evidence to record

- Build id and SHA256 of the installed DLL.
- The log, trimmed to the target lines and one count block.
- Which bosses were checked, and the result per boss.

## Rollback at any level

```bash
cd ~/Games/wotlk-clean
rm DivxDecoder.dll
mv DivxDecoder_orig.dll DivxDecoder.dll
rm -f white-model-hook.log
```
