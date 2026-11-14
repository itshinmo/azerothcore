# World data API

## When to use

To browse or test the exported world catalog without a website: entity pages, search, and spawn
sets. The contract is [specs/world-data.md](../../specs/world-data.md).

This is a development surface for the public read zone. It is not the production BFF, holds no
secret, and answers `GET` and `HEAD`; other methods return `405`. The live spawn overlay is
deferred, so `spawn-state` answers `501`.

## Prerequisites

- An export: `make world-export` (about 140,000 files, roughly 570 MB).
- Python 3.10 or newer.
- A free loopback port, default 8095.

## Steps

1. Start the server:

   ```bash
   make world-api
   ```

   It prints the export counts and the base URL, then stays in the foreground. Stop with `Ctrl-C`.

2. Query the routes:

   ```bash
   curl -s localhost:8095/api/world/meta
   curl -s localhost:8095/api/world/npc/3467
   curl -s 'localhost:8095/api/world/search?q=baron&limit=5'
   curl -s localhost:8095/api/world/npc/3467/spawns
   ```

   Routes:

   | Route | Returns |
   |-------|---------|
   | `GET /api/world/meta` | export metadata |
   | `GET /api/world/{npc,item,quest,object}/{id}` | entity document |
   | `GET /api/world/{type}/{id}/spawns` | spawn set, or a `parts` index |
   | `GET /api/world/search?q=&limit=&cursor=` | name matches, paged |
   | `GET /api/world/spawn-state` | `501`, deferred by ADR-011 |

3. Bind elsewhere if needed:

   ```bash
   make world-api ARGS="--export env/export --bind 0.0.0.0 --port 8095"
   ```

   Keep the default loopback bind unless the network is trusted. There is no authentication.

## Verification

```bash
make test-tools
curl -s localhost:8095/api/world/meta | head -c 200
curl -s -o /dev/null -w '%{http_code}\n' localhost:8095/api/world/npc/1
```

Expected: tests pass, meta prints JSON, the unknown id returns `404`.

## Troubleshooting

- ``has no meta.json; run `make world-export` first``: the export directory is missing or
  incomplete.
- `cannot bind 127.0.0.1:8095`: another process uses the port; pass `--port`.
- `500 internal`: an artifact is corrupt; re-run `make world-export`.

## Escalation

The production website will use a BFF, not this script. Keep the route shapes in sync with
`specs/world-data.md`; changing a shape is a spec change.

## References

- [specs/world-data.md](../../specs/world-data.md)
- [runbook/operation/world-export.md](world-export.md)
- [decisions/ADR-010-website-as-visual-interface.md](../../decisions/ADR-010-website-as-visual-interface.md)
