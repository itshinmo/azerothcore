# AzerothCore private server workspace

This repository is a fork of [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk), a C++20
MMORPG server emulator for World of Warcraft 3.3.5a (WotLK). It runs `authserver` and `worldserver`
against MySQL and serves game content from the world database plus client data in `DataDir`.

This fork is operated as a private server workspace. It is not upstream AzerothCore. The goal is a
maintainable, agent-friendly environment for running, operating, and extending the server without
editing immutable upstream data or losing project-specific work.

## Current focus

The current work is infrastructure and polish, not new game content:

- agent and human knowledge layer under `.ai/`, `specs/`, `decisions/`, and `runbook/`
- local development, test realm, backup, and verification tooling
- a documented database access workflow using DBeaver
- GM workflow: command handbook, least-privilege roles, audit, web panel, in-game addon

New zones, quests, dungeons, and shop features are out of scope until the foundation is stable. The
content policy and ID ranges are documented so future work does not collide with upstream IDs.

## Quickstart (macOS)

```bash
# 1. Build and install
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DSCRIPTS=static -DMODULES=static \
  -DCMAKE_INSTALL_PREFIX="$PWD/env/dist"
cmake --build build -j"$(sysctl -n hw.ncpu)"
cmake --install build

# 2. Create databases (once)
mysql -u root -p < data/sql/create/create_mysql.sql

# 3. Confirm local configuration
$EDITOR env/dist/etc/authserver.conf
$EDITOR env/dist/etc/worldserver.conf   # check DataDir and the three database strings

# 4. Start (worldserver first: it clears the realm's version-mismatch flag)
cd env/dist/bin
./worldserver
# in a second terminal:
./authserver
```

The server applies base SQL and pending updates at startup. `worldserver` needs client data under
`DataDir` (`dbc/`, `maps/`, `vmaps/`, `mmaps/`). Do not commit `env/dist/etc/*.conf`; it is ignored.

Full procedures live in [runbook/development/setup-macos.md](runbook/development/setup-macos.md) and
[runbook/operation/start-stop.md](runbook/operation/start-stop.md).

## Repository map

| Path | Holds |
|------|-------|
| `src/common/` | networking, config, logging, crypto, shared utilities |
| `src/server/game/` | core gameplay: entities, spells, quests, AI, maps, instances, handlers |
| `src/server/scripts/` | content scripts, grouped by region, class, and domain |
| `src/server/database/` | database pools, prepared statements, schema updater |
| `src/server/shared/` | code shared by auth and world servers |
| `src/server/apps/{authserver,worldserver}/` | server entry points (ports 3724 and 8085) |
| `src/test/` | Google Test unit tests and mocks |
| `e2e/` | live-stack Go e2e (AzerothGhost harness) |
| `data/sql/` | base schema, merged updates, pending updates, project SQL |
| `modules/` | external modules; project modules live in `modules/mod-*` |
| `conf/dist/` | build and shell templates (`config.cmake`, `config.sh`, `env.ac`); `conf/*.conf` is ignored |
| `src/server/apps/{authserver,worldserver}/*.conf.dist` | server config templates |
| `env/dist/` | local install prefix, binaries, configs, logs (ignored) |
| `tools/` | project tooling: dev scripts, GM addon, GM panel (future) |
| `runbook/` | human procedures: setup, operation, database, GM, troubleshooting |
| `specs/` | current behavior and contracts |
| `decisions/` | accepted decisions (ADRs) and open questions |
| `rfcs/` | proposals |
| `.ai/` | agent knowledge layer: roles, skills, memories, templates |
| `.agents/docs/` | upstream AzerothCore task-scoped coding rules |

## Knowledge map

- **Rules for agents:** [AGENTS.md](AGENTS.md)
- **How to contribute:** [CONTRIBUTING.md](CONTRIBUTING.md)
- **How the system works:** [specs/architecture.md](specs/architecture.md)
- **How to run it:** [runbook/](runbook/README.md)
- **Why decisions were made:** [decisions/](decisions/README.md)
- **Agent roles and skills:** [.ai/README.md](.ai/README.md)

## Safety

- Never commit credentials, database passwords, server keys, or player data.
- Never edit `data/sql/base/`, `data/sql/archive/`, or `data/sql/updates/db_*/`; use
  `data/sql/updates/pending_db_*/` for upstream-shaped changes and `data/sql/custom/db_*/` for
  project-specific re-applicable SQL.
- Back up the three databases before any write batch. See
  [runbook/operation/backup-restore.md](runbook/operation/backup-restore.md).
- Agents do not commit, push, or deploy. A human reviews, then the reviewer agent approves. See
  [AGENTS.md](AGENTS.md#approval-gate).
