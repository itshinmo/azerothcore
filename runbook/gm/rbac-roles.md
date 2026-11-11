# GM RBAC roles

## When to use

Creating a GM role, granting access, auditing GM accounts, or mapping a workflow to the smallest
permission set.

## Model

- `account_access.gmlevel` is a coarse level; use linked RBAC permissions for real roles.
- Commands map to `RBAC_PERM_COMMAND_*` constants in `src/server/game/Accounts/RBAC.h` and rows in
  `rbac_permissions`.
- `rbac_linked_permissions` links a role/permission group to command permissions.
- `rbac_account_permissions` grants a permission or group to an account.
- Changes are tracked SQL in `data/sql/custom/db_auth/`.

## Roles

| Role | Intended use | Includes | Excludes |
|------|--------------|----------|----------|
| `support` | player support | account/character lookup, unstuck, mute, ticket tools | item grants, bans, RBAC, server control |
| `content-tester` | testing content | teleport, GM mode, temporary spawn, instance inspect, reload | economy grants, bans, RBAC |
| `economy` | purchases and refunds | item grant, mail, money grant, refund tools | bans, RBAC, server control |
| `admin` | server administration | bans, RBAC grants, server commands | — |
| `superadmin` | named human only | all | — |

## Procedure

1. List the commands the workflow needs. Find each command's permission constant in `RBAC.h`.
2. Confirm the permission row exists in `rbac_permissions`.
3. Build the smallest group. Do not grant a broad `gmlevel` when a permission set is enough.
4. Write tracked SQL with `DELETE` + `INSERT` for the role's grants.
5. Apply to the test realm after a backup.
6. Create a dedicated test account per role.
7. Verify:
   - the role can run its commands;
   - the role is denied a higher command;
   - the audit records the action.
8. Record the role, permissions, accounts, and test result.

## Example shape

```sql
-- Illustrative only: resolve real permission IDs first.
DELETE FROM acore_auth.rbac_account_permissions
WHERE accountId = <test_account_id> AND permissionId = <group_id>;
INSERT INTO acore_auth.rbac_account_permissions
(accountId, permissionId, granted, realmId)
VALUES (<test_account_id>, <group_id>, 1, -1);
```

Never copy an ID from this example. Look it up.

## Rules

- No shared GM accounts.
- No `superadmin` for a service account.
- Production RBAC changes are human-only and backed up.
- Test denial, not only success.
- Keep the role matrix in this file current.

## Open work

The exact permission IDs and group rows are generated in Phase 4. Until then, these roles are the
design contract, not an applied preset.

## References

- [decisions/ADR-005-gm-tools-and-rbac.md](../../decisions/ADR-005-gm-tools-and-rbac.md)
- [.ai/skills/gm-rbac-management/SKILL.md](../../.ai/skills/gm-rbac-management/SKILL.md)
- [src/server/game/Accounts/RBAC.h](../../src/server/game/Accounts/RBAC.h)
