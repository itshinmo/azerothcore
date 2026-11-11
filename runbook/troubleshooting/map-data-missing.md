# Map data missing

## Symptoms

Worldserver logs map, vmap, or mmap errors; terrain is missing; creatures fall through the world;
pathfinding fails; a custom map cannot load.

## Checks

1. `DataDir` in `worldserver.conf`:

   ```bash
   grep -E '^DataDir' env/dist/etc/worldserver.conf
   ```

2. Required directories and counts:

   ```bash
   DATA_DIR="$(grep -E '^DataDir' env/dist/etc/worldserver.conf | cut -d'"' -f2)"
   for d in dbc maps vmaps mmaps; do printf '%s: ' "$d"; ls "$DATA_DIR/$d" | wc -l; done
   ```

3. Look for the specific map ID in the logs:

   ```bash
   grep -nE 'map|vmap|mmap|DataDir' env/dist/logs/Errors.log | tail -n 80
   ```

4. Confirm the map exists in `map_dbc` or the client `Map.dbc`:

   ```sql
   SELECT ID, Directory, InstanceType FROM acore_world.map_dbc WHERE ID = ?;
   ```

## Fixes

- **Missing directory:** point `DataDir` at the extracted data root.
- **Missing base data:** run the extractors (`map_extractor`, `vmap4_extractor`, `vmap4_assembler`,
  `mmaps_generator`) on a client copy. `TOOLS_BUILD=all` builds them.
- **Missing single map:** extract that map, or check that the client patch includes it.
- **Custom map:** the client needs a Map.dbc/MPQ patch, and the server needs the extracted `.map`,
  `.vmap`, and `.mmap` files. A `map_dbc` row alone is not enough.
- **Wrong case/path:** macOS is case-insensitive by default, Linux is not. Use the exact directory
  names.

## Rules

- Do not copy map files from an unlicensed client.
- Do not edit `DataDir` while the server is running.
- Do not assume a missing map is a code bug; check the data first.
- Custom maps need a client patch and a release plan.

## Verification

- The map loads without errors.
- Terrain, collision, and pathfinding work.
- A GM can teleport to the map and move.

## References

- [specs/content-pipeline.md](../../specs/content-pipeline.md)
- [apps/extractor](../../apps/extractor)
- [.agents/docs/build.md](../../.agents/docs/build.md)
