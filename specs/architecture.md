# Architecture

## Purpose

Describe the current system so a human or agent can change it without rediscovering the runtime.
This spec covers structure and extension points, not every gameplay rule.

## Scope

- Process topology: `authserver`, `worldserver`, MySQL, client data.
- Core module layout and threading model.
- Script and module registration.
- Content and database data flow.
- Project tooling.

## Boundary

Owns: the C++ core, server runtime, script/module loading, database access patterns.

Does not own: individual boss mechanics, quest rewards, or item balance; those live in content scripts
and data. Does not own the database clients or GM panel; see their docs.

## Runtime

```text
client
  |  SRP6 login, realm list
  v
authserver :3724  --->  acore_auth
  |
  |  realm address
  v
worldserver :8085  --->  acore_world, acore_characters
  |  world loop, map workers, session handlers
  v
DataDir: dbc/, maps/, vmaps/, mmaps/
```

- `authserver` handles account authentication, realm list, bans, and session keys.
- `worldserver` loads configuration, databases, SQL updates, DBC stores, maps, scripts, SmartAI,
  conditions, items, quests, and game events, then starts the network and world loop.
- The world thread updates sessions and timers. Map updates run on worker threads. Packet handlers are
  classified thread-safe or thread-unsafe; unsafe handlers run on the world thread.
- Database access uses three connection pools and prepared statements. Long reads are asynchronous;
  multi-statement writes use `SQLTransaction`.

## Core modules

| Area | Path |
|------|------|
| Networking and sessions | `src/server/shared/Network/`, `src/common/Asio/`, `src/server/game/Server/` |
| Entities | `src/server/game/Entities/` |
| Maps and instances | `src/server/game/Maps/`, `src/server/game/Instances/` |
| Spells and auras | `src/server/game/Spells/` |
| Quests | `src/server/game/Quests/` |
| AI | `src/server/game/AI/` |
| Scripting | `src/server/game/Scripting/` |
| Conditions | `src/server/game/Conditions/` |
| Database | `src/server/database/` |
| Content scripts | `src/server/scripts/` |
| Modules | `modules/` |

## Script and module registration

- Content scripts register through `AddSC_*` loaders.
- Spell/aura scripts use `RegisterSpellScript` or `RegisterSpellAndAuraScriptPair`.
- Creature AI prefers `RegisterCreatureAI`; instance scripts use `RegisterInstanceScript`.
- Script registration happens during startup. The script registry is read concurrently and must not
  be modified afterward.
- A `SpellScript` without a `spell_script_names` row is inert.
- Modules are auto-discovered from `modules/<name>/`; project modules use `modules/mod-*`.
- Modules can implement hooks, commands, scripts, and their own SQL. They must not require edits to
  upstream core files.

## Extension points

| Goal | Where |
|------|-------|
| New creature behavior | SmartAI SQL; C++ script only if SmartAI cannot express it |
| New spell/aura behavior | `src/server/scripts/Spells/` or a module, plus `spell_script_names` |
| New instance | `InstanceMapScript` + `instance_template` + spawns + `instance_encounters` |
| New command | `CommandScript` + loader |
| New hook | `ScriptDefines/` + call site; prefer a module |
| New prepared query | `src/server/database/Database/Implementation/WorldDatabase.*` |
| New config | `WorldConfig.h/.cpp` + `worldserver.conf.dist` |
| Project feature | `modules/mod-*`, tracked SQL, or `tools/` |

## Constraints

- Never store a raw `Player*`, `Creature*`, or `Unit*` past the current call; use `ObjectGuid`.
- Never modify the script registry after startup.
- Never block the world thread on a long query.
- Never edit immutable SQL trees.
- New maps or visuals need a client patch; reuse existing assets first.
