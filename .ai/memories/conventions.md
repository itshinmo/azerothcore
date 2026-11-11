---
description: C++, SQL, Node, ID, logging, secret, and documentation conventions. Read before writing code or data.
last-verified: 2026-11-12
---

# Conventions

Binding rules: [AGENTS.md](../../AGENTS.md) and `.agents/docs/`. This note records the patterns behind
them.

## C++

- C++20, Allman braces, 4-space indent, max 120 columns, LF, final newline.
- `auto const&`, `Type const*`, `if (x)`, no braces around single-line statements.
- `fmt`-style `{}` format specifiers, never printf-style.
- Logging: `LOG_INFO("category.sub", "message {}", arg)`; no `printf`, `sLog->`, or `TC_LOG_*`.
- Random: helpers in `src/common/Utilities/Random.h`; never `std::rand` or `<random>`.
- Strings: `Acore::StringFormat`.
- Config: read once at startup/reload and cache; never in a hot path.
- Namespace: `Acore::`. Do not leave `Trinity::` names in ported code.
- Never store a raw `Player*`, `Creature*`, or `Unit*` past the current call; store `ObjectGuid` and
  resolve at use time.
- Database: `PreparedStatement` plus typed enums; async reads through `_queryProcessor`; writes in a
  `SQLTransaction`.
- AI timers: `EventMap` or `TaskScheduler`, not custom tick counters.
- Script ids: named enum entries, never raw literals.

## SQL

- Every `INSERT` has a matching `DELETE` for idempotency.
- Spawn `DELETE` and `UPDATE` target one table, filter on `id` and `guid`, never `OR`.
- No double semicolons, no multiple blank lines, InnoDB, backticks, final newline.
- `smart_scripts` edits rewrite the full `(entryorguid, source_type)` block.
- Do not edit `base/`, `archive/`, or `updates/db_*/`.
- Project SQL in `custom/db_*/` must be re-applicable.
- Respect the custom ID ranges in `runbook/database/id-registry.md`.

## Node

- Node 26 ESM. Prefer built-in modules. `tools/dbadmin` (phase 3) uses only `mysql2` as a runtime
  dependency.
- No framework, no build step for the GUI. Server-rendered HTML, small vanilla JS.
- All input validated; all SQL parameterized; all writes audited.
- `node:test` for unit tests. No hidden global state between tests.

## Logging

- Server logs: `LOG_*` with a hierarchical category.
- GUI/tool logs: structured lines with timestamp, level, component, and no secrets.
- Never log passwords, tokens, session keys, full SQL containing secrets, or player personal data.

## Configuration and secrets

- Local server config: `env/dist/etc/*.conf` (ignored).
- Tool config: `.env` files (ignored) with `.env.example` committed.
- Production secrets are never in the repository or agent chat.
- Use least-privilege database users. Never `root` for tools or agents.

## Documentation

- Current behavior goes in `specs/`, decisions in `decisions/`, procedures in `runbook/`.
- Link, do not duplicate. Update the index when adding a file.
- Facts only. Unknowns are `<!-- TODO -->` plus a question, not a guess.
- No secrets, production hostnames, player data, or internal URLs.
