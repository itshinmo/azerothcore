---
name: gm-rbac-management
description: Use when creating a GM role, granting or revoking a permission, auditing GM accounts, or mapping a workflow to the smallest permission set.
---

# gm-rbac-management

## Prerequisites

- The `rbac_*` schema: `rbac_permissions`, `rbac_linked_permissions`, `rbac_account_permissions`,
  `rbac_default_permissions`.
- The command-to-permission mapping in `runbook/gm/rbac-roles.md`.
- A backup of `acore_auth`.

## Workflow

1. Define the workflow and the minimum commands it needs.
2. Map each command to its `RBAC_PERM_COMMAND_*` constant in
   `src/server/game/Accounts/RBAC.h` and the `rbac_permissions` table.
3. Choose the smallest role:
   - `support` — read-only account/character lookup, unstuck, mute.
   - `content-tester` — teleport, GM mode, temporary spawn, instance inspect.
   - `economy` — item/mail grants and refunds, audited.
   - `admin` — bans, RBAC, server commands.
   - `superadmin` — all; restricted to named human accounts.
4. Apply changes through tracked SQL, not ad-hoc `UPDATE`s.
5. Test with a dedicated account per role on the test realm.
6. Verify that a lower role is denied a higher command.
7. Record the role, permissions, accounts, and test result.

## Constraints

- Never grant `superadmin` to a shared or service account.
- Never edit `rbac_permissions` IDs or names to make a grant easier.
- Never grant a permission by name you have not found in the schema.
- Never use `gmlevel` alone as a role model; use linked permissions.
- Production RBAC changes are human-only, backed up, and audited.

## Expected output

A role matrix, the SQL applied, test-account results, and a rollback note.

## References

- [runbook/gm/rbac-roles.md](../../../runbook/gm/rbac-roles.md)
- [src/server/game/Accounts/RBAC.h](../../../src/server/game/Accounts/RBAC.h)
- [.agents/docs/sql-guidelines.md](../../../.agents/docs/sql-guidelines.md)
