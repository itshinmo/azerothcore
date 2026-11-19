---
description: What this repository is, its current state, the scope of work, and where to start. Read first on any task.
last-verified: 2026-11-19 (phases: base game, custom content, website, launch)
---

# Overview

This is a private-server fork of **AzerothCore**, a C++20 server emulator for World of Warcraft
3.3.5a (WotLK). It runs `authserver` and `worldserver` against MySQL. Game content lives mostly in the
world database; client data (DBC, maps, vmaps, mmaps) lives in `DataDir`.

The fork is not upstream AzerothCore. Upstream code is kept mergeable; project-specific work lives in
tracked modules, tracked SQL, and project tooling.

## Current phase

Base game first. The phases are: base game fully functional and stable, custom content, website,
launch. The work now is:

- base-game verification: scripts, quests, NPC spawns and behavior, client-observed behavior,
  stability
- agent and human knowledge layer
- local development, test realm, backup, and verification tooling
- database access through DBeaver (no in-repo database GUI)
- GM workflow: handbook, RBAC, audit, GM API, in-game addon; visual layer moves to the future server
  website in Phase 3
- playtests and a friends-only test VPS as needed
- manual verification by the owner; the bot rig is paused and kept for a future resume
  ([ADR-017](../../decisions/ADR-017-bot-rig-paused.md))

The website starts after the base game and custom content
([ADR-013](../../decisions/ADR-013-server-and-client-before-website.md)). API-first still applies
while it waits. Custom content, new zones, quests, dungeons, items, and shop features are out of
scope until the base game is stable. The content policy and ID ranges are documented so future work
does not collide.

## Verified local state

- Build: `build/`, Release, Apple clang, `SCRIPTS=static`, `MODULES=static`, PCH on.
- Install prefix: `env/dist/` with `bin/authserver`, `bin/worldserver`, `etc/`, `logs/`.
- MySQL 8.4 is used. Databases `acore_auth`, `acore_characters`, and `acore_world` are imported;
  isolated test databases are `acore_test_auth`, `acore_test_characters`, `acore_test_world`.
- Client data: `DataDir` points to a local `Data/` tree with `dbc/`, `maps/`, `vmaps/`, `mmaps/`.
- Ports: local authserver 3724, worldserver 8085; test realm authserver 3824, worldserver 8185.
- Test realm: built and usable with `make test-realm CMD=setup|start|stop|status|reset`; see
  [runbook/operation/test-realm.md](../../runbook/operation/test-realm.md). Production: not deployed.
  Warden is on in the local config and must be off on the dedicated e2e test realm.

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
