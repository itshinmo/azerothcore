---
name: gm-command-handbook
description: Use when a GM needs to find, explain, or safely run an in-game command, or when updating the command handbook.
---

# gm-command-handbook

## Prerequisites

- The GM's role and the smallest permission that can do the job.
- The target player, character, or account.
- The handbook entry: syntax, side effects, danger level, permission.

## Workflow

1. Find the command in [runbook/gm/command-handbook.md](../../../runbook/gm/command-handbook.md) or
   in-game `.help <command>`.
2. Confirm the GM role has the permission; see
   [runbook/gm/rbac-roles.md](../../../runbook/gm/rbac-roles.md).
3. Prefer a read-only command first: `.lookup`, `.character`, `.account`, `.npc info`, `.quest status`.
4. For a write, state the target and expected change before running it. For destructive actions, get
   a second confirmation.
5. Run the command. Record the exact command and the observed result.
6. Verify the outcome with a read-only command or a DB query.
7. For item, gold, or account changes, use a wrapped command now; the future website will use the audited API; never raw SQL.

## Danger levels

- **read** — lookup and inspection.
- **low** — teleport, GM mode, temporary spawn.
- **medium** — item grant, mail, quest state, instance reset.
- **high** — ban, account change, mass mail, despawn, economy grant.
- **critical** — server shutdown, RBAC change, character deletion, database-wide operation.

High and critical actions require human approval and an audit entry.

## Constraints

- Never share a GM account. Use named accounts.
- Never run a mass command on all players without approval.
- Never use `.gm on` during a fight to hide from a test; use the e2e damage helpers.
- Never grant from untrusted input.
- Never post player data or secrets in the handbook or a report.

## Expected output

The command, permission, target, result, verification, and audit reference.

## References

- [runbook/gm/command-handbook.md](../../../runbook/gm/command-handbook.md)
- [runbook/gm/rbac-roles.md](../../../runbook/gm/rbac-roles.md)
- [src/server/scripts/Commands](../../../src/server/scripts/Commands)
