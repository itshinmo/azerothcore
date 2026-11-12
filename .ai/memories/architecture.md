---
description: Runtime flow, core modules, content pipeline, scripting, modules, and project tooling. Read before changing structure.
last-verified: 2026-11-12 (source map and startup sequence checked 2026-11-11)
---

# Architecture

The contract is [specs/architecture.md](../../specs/architecture.md). This note is orientation.

## Runtime

- `authserver` (3724) handles SRP6 login, account lookup, and the realm list from `acore_auth`.
- `worldserver` (8085) loads configuration and databases, applies SQL updates, loads DBC stores, maps,
  scripts, SmartAI, conditions, and items, then starts network threads and the world loop.
- The world thread updates sessions and timers. Map updates run on worker threads. Packet handlers are
  classified thread-safe or thread-unsafe; unsafe handlers run on the world thread.
- Database work uses connection pools for auth, characters, and world. Use prepared statements and
  async callbacks; never block the world thread on a long query.

## Core modules

| Area | Path | Notes |
|------|------|-------|
| Networking | `src/server/shared/Network/`, `src/common/Asio/`, `src/server/game/Server/` | Asio sockets, world session, opcode table |
| Entities | `src/server/game/Entities/` | Player, Creature, Unit, Item, GameObject, Vehicle |
| Maps and instances | `src/server/game/Maps/`, `src/server/game/Instances/` | map update workers, instance saves, InstanceScript |
| Spells and auras | `src/server/game/Spells/` | spell stores, effects, aura scripts |
| Quests | `src/server/game/Quests/` | quest definitions, status, rewards |
| AI | `src/server/game/AI/` | SmartAI, EventMap, TaskScheduler |
| Scripting | `src/server/game/Scripting/` | ScriptMgr, hooks, script registry |
| Conditions | `src/server/game/Conditions/` | polymorphic `conditions` table |
| Database | `src/server/database/` | pools, prepared statements, schema updater |

## Script registration

- Content scripts live under `src/server/scripts/` and register through `AddSC_*` loaders.
- Spell/aura scripts use `RegisterSpellScript` or `RegisterSpellAndAuraScriptPair`.
- Creature AI prefers `RegisterCreatureAI`; legacy zones use `new ClassName()`.
- Instances use `RegisterInstanceScript`.
- A `SpellScript` without a matching `spell_script_names` row is inert. Ship the SQL in the same
  change.
- Script pointers must be registered during startup and must not be modified afterward.

## Modules

- Modules live in `modules/<name>/`, each with its own `CMakeLists.txt`.
- Project modules are tracked under `modules/mod-*`.
- Modules can implement hooks, commands, scripts, and their own SQL under
  `modules/<name>/data/sql/<db-dir>/`.
- Do not require edits to upstream core files. If a core hook is missing, open an RFC.

## Content pipeline

- Three databases: `acore_auth`, `acore_characters`, `acore_world`.
- SQL tree: `base/` for an empty database, `updates/db_*/` for merged releases, `pending_db_*/` for
  in-flight upstream-shaped changes, `custom/db_*/` for re-applicable project SQL.
- The server applies base SQL when a database is empty, then files from `updates_include` at startup.
- World content is mostly data: creature templates and spawns, quest templates, items, gameobjects,
  SmartAI, conditions, instance templates, loot, and `spell_script_names`.
- Server-side DBC overlays exist (`spell_dbc`, `map_dbc`, `areatable_dbc`, `item_dbc`, …). Genuinely
  new maps, zones, item visuals, spell visuals, and area triggers need a client patch plus map
  extraction. Reusing existing assets does not.

## Project tooling

- `tools/dev/` — doctor, server lifecycle, database, verification, logs.
- `tools/` — project tooling: dev scripts, GM addon. Database access uses DBeaver, not an in-repo
  server. The long-term visual layer is the server website (ADR-010); no in-repo web UI now.
- `tools/gm-addon/` — in-game GM command menu (built).
- `modules/mod-gm-audit/`, `modules/mod-gm-api/` — GM audit and API (phase 4).
