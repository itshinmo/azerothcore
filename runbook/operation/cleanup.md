# Cleanup — reclaim disk space

Removes disposable build, backup, and log artifacts. Dry-run by default; nothing is deleted without
`--yes`. Bot-rig data is never touched ([ADR-017](../../decisions/ADR-017-bot-rig-paused.md)).

## Usage

```bash
make cleanup                          # dry run: list what would go
make cleanup ARGS="--yes"             # delete
tools/dev/cleanup.sh --help           # same options without make
```

| Option | Default | Effect |
|---|---|---|
| `--yes`, `-y` | off | Delete. Without it the script only reports sizes |
| `--backups-keep N` | `7` | Keep the N newest dump directories in `var/backups/manual/` and `var/backups/verify/`; N must be at least 1 |
| `--logs-days N` | `7` | Delete main-server `*.log*` older than N days in `env/dist/logs/` |

## What it removes

- `build-verify/` — the `verify-cpp` build tree; recreated by the next `make verify-cpp`.
- Old database dumps under `var/backups/`. The newest N dumps of each type stay. This is stricter
  than the 14-day prune in `tools/dev/backup.sh`; the dumps themselves are unchanged.
- Age-gated main-server logs. Active logs have a current mtime and are never matched.

## What it never touches

- Game clients, `build/`, `.git`, `data/sql/`, and the rig's `build/` tree.
- The bot rig: its databases, worktree, traces, logs, and ledger are kept as reproduction material.
- `env/dist/` except the age-gated logs.
- The newest backup dump, rollback binaries such as `worldserver.pre-*` (not matched by any rule).

## Safety

- Dry run unless `--yes` is passed.
- Refuses to delete `build-verify` while a `verify-cpp` build is active.

## Weekly schedule on the VPS

```cron
0 4 * * 0 /opt/azerothcore/tools/dev/cleanup.sh --yes >> "$HOME/azcore-cleanup.log" 2>&1
```

Sunday 04:00. Run it as the account that owns the checkout, so the log path is writable and the
files are deletable. `tools/dev/common.sh` adds Homebrew paths, so the script also runs from `cron`
and `launchd` with a minimal `PATH`.

## Related

- [backup-restore.md](backup-restore.md) — dumps and retention.
- [logs-and-monitoring.md](logs-and-monitoring.md) — where the logs live.
- [playerbot-rig.md](playerbot-rig.md) — the paused rig and its kept data.
