# ADR-009 — RBAC command permission precedence

- Status: accepted
- Date: 2026-11-12
- Amends: [ADR-005](ADR-005-gm-tools-and-rbac.md)

## Context

The world database `command` table stores a legacy `security` value as `tinyint unsigned`. Valid
legacy levels are `0-4`; RBAC command permissions go up to `945`. The column stores `0-255`, so ids
above `255` cannot be stored, and legacy values overlap the low RBAC range.

At startup, the command loader replaced the core command permission with the value from the
`command` table. A row such as `account create = 4` therefore removed RBAC permission `219`. The
five role presets were ineffective for every command whose row still had a legacy value.

ADR-005 allows a minimal core patch when required. This is that patch.

## Decision

1. When a command's core permission is greater than `SEC_CONSOLE` (`4`), the core permission is
   authoritative. The legacy `command.security` value is ignored.
2. When both the core permission and the database value are legacy `0-4` values, the database value
   still overrides the core, preserving existing server customization.
3. The world `command` schema is not changed. The RBAC tables remain the source of command
   authorization.
4. The patched file is `src/server/game/Chat/ChatCommands/ChatCommand.cpp`.

## Alternatives considered

- **Change `command.security` to `int unsigned` and store RBAC ids.** Requires a schema change and a
  loader change, and makes the legacy and RBAC value spaces overlap. Rejected as larger and more
  error-prone.
- **Generate 600+ `UPDATE command` rows.** Cannot store ids above `255` in the current column.
- **Leave the override.** RBAC presets do not work; rejected.

## Consequences

- RBAC role presets now control command access.
- A database `command.security` value no longer overrides an RBAC command permission. Use the RBAC
  tables for that.
- Legacy commands keep their existing database override behavior.
- The change was verified by the live five-role test; `make verify-full` covers the build, lint, and
  unit suite.
