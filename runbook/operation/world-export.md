# World data export

## When to use

Before publishing or updating the public world catalog, or when the content audit and the site must
agree on what exists in the database.

Read-only. It never writes to the database.

## Prerequisites

- MySQL running with `acore_world` reachable through `env/dist/etc/worldserver.conf`.
- `mysql` client and `python3` 3.10 or newer.
- Free disk for the output. A full export is about 140,000 files and roughly 570 MB.

## Steps

1. Export:

   ```bash
   make world-export
   ```

   Default output is `env/export` (gitignored). The command prints the meta document:

   ```json
   {
     "schemaVersion": 1,
     "sourceDatabase": "acore_world",
     "sourceDatabaseVersion": "ACDB 335.17-dev",
     "counts": {"npc": 29945, "item": 46096, "quest": 9464, "object": 21580,
                "spell": 0, "spawns": 33318, "parts": 208},
     "durationSeconds": 25.2
   }
   ```

   `generatedAt` and `buckets` are also present.

2. Replace an existing export:

   ```bash
   make world-export ARGS="--force"
   ```

   Without `--force`, a non-empty output directory is refused.

## Verification

```bash
make test-tools
make verify-docs
make world-export ARGS="--force"
```

Expected: tests pass, docs check is green, the export finishes in well under a minute and prints
counts that match `SELECT COUNT(*)` for `creature_template`, `item_template`, `quest_template`, and
`gameobject_template`.

Spot check: `env/export/npc/3467.json` (Baron Longshore), `env/export/quest/57.json`
(The Night Watch), and `env/export/spawns/npc/3467.json` (three Tanaris spawn points).

## Troubleshooting

- `refusing database '...'`: the config must point at a database whose name ends in `_world`.
- `is not empty; pass --force`: delete the directory or pass `ARGS="--force"`.
- `refusing to replace ... no meta.json`: the target is not an export directory; delete it or point
  `--output` elsewhere.
- Interrupted run: the previous export is in `env/export.old`, the partial one in
  `env/export.tmp`. Move `.old` back or re-run with `--force`.
- Disk full: export to another path with `ARGS="--output /path"`.
- Counts lower than expected: the database was not fully imported; run `make doctor`.

## Escalation

The artifact format is the public contract in [specs/world-data.md](../../specs/world-data.md).
Changing it is a spec change; do not edit generated files by hand.

## References

- [specs/world-data.md](../../specs/world-data.md)
- [decisions/ADR-011-world-data-and-content-verification.md](../../decisions/ADR-011-world-data-and-content-verification.md)
- [content-audit.md](content-audit.md)
