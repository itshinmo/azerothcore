---
description: What this repository is, its current state, the scope of work, and where to start. Read first on any task.
last-verified: 2026-11-12 (foundation phase start; local build and databases verified 2026-11-11)
---

# Overview

This is a private-server fork of **AzerothCore**, a C++20 server emulator for World of Warcraft
3.3.5a (WotLK). It runs `authserver` and `worldserver` against MySQL. Game content lives mostly in the
world database; client data (DBC, maps, vmaps, mmaps) lives in `DataDir`.

The fork is not upstream AzerothCore. Upstream code is kept mergeable; project-specific work lives in
tracked modules, tracked SQL, and project tooling.

## Current phase

Foundation, not content. The work is:

- agent and human knowledge layer
- local development, test realm, backup, and verification tooling
- database GUI (`tools/dbadmin/`, planned phase 3)
- GM workflow: handbook, RBAC, audit, web panel, in-game addon

New zones, quests, dungeons, items, and shop features are out of scope until the foundation is
stable. The content policy and ID ranges are documented so future work does not collide.

## Verified local state

- Build: `build/`, Release, Apple clang, `SCRIPTS=static`, `MODULES=static`, PCH on.
- Install prefix: `env/dist/` with `bin/authserver`, `bin/worldserver`, `etc/`, `logs/`.
- MySQL 8.4 is used. Databases `acore_auth`, `acore_characters`, and `acore_world` are imported.
- Client data: `DataDir` points to a local `Data/` tree with `dbc/`, `maps/`, `vmaps/`, `mmaps/`.
- Ports: authserver 3724, worldserver 8085.
- Test realm: planned; production: not deployed. Warden is on in the local config and must be off on
  the dedicated e2e test realm.

## Where things are

- Rules: [AGENTS.md](../../AGENTS.md)
- Workflow: [CONTRIBUTING.md](../../CONTRIBUTING.md)
- Architecture: [specs/architecture.md](../../specs/architecture.md)
- Database: [specs/database.md](../../specs/database.md)
- Procedures: [runbook/](../../runbook/README.md)
- Decisions: [decisions/](../../decisions/README.md)
- Upstream coding rules: [.agents/docs/](../../.agents/docs/README.md)

## Non-negotiable boundaries

- No secrets, credentials, player data, or production values in the repository.
- No edits to `data/sql/base/`, `archive/`, or `updates/db_*/`.
- No production writes by agents.
- No agent commit, push, or deploy without human and reviewer approval.
- Custom content uses tracked modules and tracked SQL, with reserved ID ranges.
