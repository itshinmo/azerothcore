---
description: C++, SQL, Node, ID, logging, secret, documentation, and 3.3.5 client addon conventions. Read before writing code, data, or addon Lua.
last-verified: 2026-11-22 (23bf75546)
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

## Logging

- Server logs: `LOG_*` with a hierarchical category.
- Tool logs: structured lines with timestamp, level, component, and no secrets.
- Never log passwords, tokens, session keys, full SQL containing secrets, or player personal data.

## Configuration and secrets

- Local server config: `env/dist/etc/*.conf` (ignored).
- Tool config: `.env` files (ignored) with `.env.example` committed.
- Production secrets are never in the repository or agent chat.
- Use least-privilege database users. Never `root` for tools or agents.

## 3.3.5 client addons

- `GetItemInfo` has no numeric class return and no `LE_ITEM_CLASS_*` globals; the item class
  arrives as a localized string ("Armor"/"Weapon" plus client-locale variants — see
  mod-transmog-plus's `ItemClassStrToNum`).
- The bag API numbers every bag's slots 1..N; the server numbers the backpack 23..38
  (`INVENTORY_SLOT_ITEM_START`) and equipped bags 19..22 (`INVENTORY_SLOT_BAG_START`). Translate
  before sending a slot to the server.
- Container item buttons are created lazily, so a per-button hook attached at login fires on
  nothing; hook the globals (`ContainerFrameItemButton_OnClick`, `UseContainerItem`) instead.
- SecureActionButton attributes can switch action type at runtime (`type` item↔spell; assigning
  nil clears one), subject to combat-lockdown rules.

## Documentation

- Current behavior goes in `specs/`, decisions in `decisions/`, procedures in `runbook/`.
- Link, do not duplicate. Update the index when adding a file.
- Facts only. Unknowns are `<!-- TODO -->` plus a question, not a guess.
- No secrets, production hostnames, player data, or internal URLs.
