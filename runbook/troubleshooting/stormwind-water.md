# Stormwind canal water and swim animation

## Symptoms

Jumping into a Stormwind canal makes the character fall to the canal floor. The client shows
underwater fog and the Breath bar, but the character does not swim and cannot rise. The water
surface is visible above. Reproduced 2026-11-14 on the patched client and 2026-11-15 on a clean
3.3.5a build 12340 client on a stock client data set.

## Root cause and fix (2026-11-15)

The WoWSilicon mod `mods/libSiliconPatch.dll` (an x87 to SSE2 function rewrite) breaks the client's
WMO liquid lookup. Disabling it restores swimming with no server change:

1. Comment `mods/libSiliconPatch.dll` out in `dlls.txt`.
2. Relaunch the client and re-enter the canal.

Verified: same client and server, mod off swims, mod on sinks. Players with identical client files
but without `libSiliconPatch` swim normally. Reported upstream as
[WoWSilicon#67](https://github.com/WoWSilicon/WoWSilicon/issues/67); the DLL bundled with WoWSilicon
2.5.3 and 3.2.2 both reproduce.

The client data is not involved: all 246 DBCs and all 5744 map files extracted from the played
client are byte-identical to the server's `DataDir`. The server is not involved either: its VMap
reports water entry 13 at `95.474075` over a floor at `85.891525`, and the client renders that
water.

## Measured 2026-11-15 (stock client data, libSiliconPatch enabled)

Character `Admin`, map 0, Stormwind canals. GM mode was off; `.cheat god` was on to survive
drowning.

Server `.gps` at the canal floor:

```text
X -8715.615 Y 572.98004 Z 85.89157
Liquid level: 95.474075, ground: 85.891525, type: 13, flags 1, status: 8
```

| Probe | Result |
| --- | --- |
| Server view | liquid entry 13, flags 1 (water), surface `95.474075`, floor `85.891525`; player 9.58 yd under |
| Client `IsSwimming()` on the floor | nil (not swimming) |
| Client after a drop at `Z 96.5`, 1 yd under the surface | sank through to the floor, no swim entry |
| Client `IsFalling()` on the floor | nil (grounded) |
| Camera | inside the water volume, underwater fog renders |
| Breath bar | shown (server-driven) |
| Space held 2 s on the floor | no rise, no jump |
| Control: terrain liquid, Eastern Strand `-1376 -1012 1` | swims at the surface, Breath bar clears |

Conclusion: this client renders the canal water and the server reports deep water, but the client
never enters swim state in WMO liquid entry 13. Terrain liquid works in the same client and session.
Movement keys and chat work. Swim state is client-only; the server only computes breath, which is
why the Breath bar appears while the character sinks. The cause is `libSiliconPatch`, see above.

## First checks

1. Confirm the server sees water at the exact spot:

   ```text
   .gps
   ```

   Observed at X `-8713.321` Y `573.60785` Z `85.89216`, grid `[48,30]` cell `[2,7]`:

   ```text
   GroundZ: 59.4562 FloorZ: 85.891525 Have height data (Map: 1 VMap: 1 MMap: 1)
   Liquid level: 95.474075, ground: 85.891525, type: 13, flags 1, status: 8
   ```

   `status: 8` is `LIQUID_MAP_UNDER_WATER`. Type 13 is WMO water. The server thinks the player is
   9.58 yards below the surface. This is correct deep water, not a shallow-water spot.

2. Confirm GM mode is off:

   ```text
   .gm
   ```

   It was off during every reproduction.

3. Confirm the client's own view, in the same spot:

   ```text
   /run print("isSwim", IsSwimming(), "falling", IsFalling())
   ```

4. Control test in terrain water (any lake, river, or ocean) in the same client session. This
   separates a client-wide swim failure from the WMO liquid case.

5. If a second WMO water body is reachable, repeat steps 1 to 3 there.

## Reproducing a player report at another location

Players may report more spots with the same behaviour. Do not guess and do not add fake liquid to
server data. Procedure:

1. Ask the player to log out standing in the reported spot, then read the saved position:

   ```sql
   SELECT name, map, position_x, position_y, position_z, zone
   FROM acore_characters.characters WHERE name = '<name>';
   ```

2. On a GM character, teleport 2 yards above that point and let the character fall in:

   ```text
   .go xyz <x> <y> <z+2>
   ```

3. Record the server view and the client view:

   ```text
   .gps
   /run print("isSwim", IsSwimming(), "falling", IsFalling())
   ```

4. Hold jump for 2 seconds. Record whether the character rises, jumps, or stays on the floor, and
   run `.gps` again to compare Z.

5. Control test in terrain water with the same client. If that swims, the report is the WMO liquid
   case described here.

6. Write down: zone, coordinates, server liquid entry and status, client `IsSwimming()`, and whether
   the character rose.

Until the client side is fixed, unstick the player with `.unstuck` or teleport them out. Nothing in
the server configuration or SQL changes the outcome.

`PacketLogFile` alone is not enough: `PacketLog` opens the file on the first packet, but packets are
only written for sessions that enabled logging with `.packetlog on` (RBAC-gated), so a copied config
value produces an empty file.

## Interpretation

- Server-side water state is correct. The swim state is client-side: the client decides the swim
  animation, the swim speed, and the vertical movement; the server records the swim flag and applies
  underwater state and breath from its own map/VMap liquid.
- The canals are WMO water. The ADT `.map` has no liquid inside the city canals; do not add fake ADT
  liquid to "fix" the server. The server's VMap liquid already reports type 13, level 95.47, and
  status 8 at the spot.
- GM mode was ruled out, and so was the HD patch set: a clean client reproduces.
- The cause is the `libSiliconPatch` x87 rewrite, not the data and not the server. Disabling the mod
  restores swimming, and enabling it brings the sink back, on the same client and server.

## Clean client rule

Behaviour that lives in the client (swimming, collision, animation, spell visuals) is verified on a
client without performance DLL mods. `libSiliconPatch` altered swim behaviour, so the patched play
client is not authoritative. Keep a second client copy for verification, for example
`~/Games/wotlk-test` with `mods/libSiliconPatch.dll` commented out in `dlls.txt`.

## Security and cheating

- The authserver verifies the account and the accepted client build (12340). By default it does not
  verify the executable checksum; `StrictVersionCheck=1` adds an executable SHA1 proof from
  `build_info`. MPQs are not hashed at login.
- Warden is runtime anti-cheat, not a full client file-integrity scan, and it covers `Win` clients
  only. Custom HD MPQs are not checked. Client-trust contract:
  [specs/security.md](../../specs/security.md).
- Client rendering, collision, and animation are not server-authoritative. A modified client can
  skip the swim animation or walk underwater. The server still applies underwater state and breath
  from the map/VMap liquid, but it does not force the swim animation. Server-side water movement
  validation is not implemented.
- With `Warden` on, a modified client can be rejected or flagged; client-trust testing belongs on a
  stack with Warden off (the future `dev`/`ptr` realms, [ADR-018](../../decisions/ADR-018-realm-strategy.md)).
- This is a general 3.3.5a client-trust gap, not a GM or RBAC bypass. GM mode is server-granted.

## Next steps

1. Keep `libSiliconPatch` off until a fixed DLL ships, and re-test after each WoWSilicon update
   against [issue #67](https://github.com/WoWSilicon/WoWSilicon/issues/67). Keep a second client copy
   without the mod for behaviour checks, for example `~/Games/wotlk-test` with the line commented out
   in `dlls.txt`.
2. The data check is done: the played client's 246 DBCs and 5744 map files are byte-identical to
   `DataDir`. A vmap comparison is order-sensitive and was inconclusive; it is not needed now.

## References

- [specs/security.md](../../specs/security.md)
- [specs/server.md](../../specs/server.md)
- [map-data-missing.md](map-data-missing.md)
- [runbook/gm/command-index.md](../gm/command-index.md)
- [WoWSilicon issue #67](https://github.com/WoWSilicon/WoWSilicon/issues/67)
