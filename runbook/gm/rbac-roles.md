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
- RBAC command permissions (`>= 200`) are authoritative. The world `command` table still stores
  legacy `0-4` security levels; the core ignores them for RBAC commands.
- Changes are tracked SQL in `data/sql/custom/db_auth/`.

## Roles

| Role | Intended use | Includes | Excludes |
|------|--------------|----------|----------|
| `support` (950100) | player support | lookup, unstuck, mute, tickets | grants, bans, RBAC, server |
| `content-tester` (950101) | testing content | teleport, GM mode, temp spawn, inspect, reloads | grants, bans, RBAC |
| `economy` (950102) | purchases and refunds | item/mail grants, refunds | bans, RBAC, server |
| `admin` (950103) | server administration | bans, RBAC, server | — |
| `superadmin` (950104) | named human only | all permissions | — |

Group IDs are allocated from the misc range `950000–959999` in the auth database; they do not collide
with world content IDs. `content-tester` has no `.npc delete`; temporary spawns disappear on restart.

## Presets

Tracked SQL: `data/sql/custom/db_auth/gm_rbac_presets.sql`. The examples below use `acore_auth`;
substitute `acore_test_auth` on the test realm.

- The file upserts the five role rows and replaces their linked permissions. It never deletes a role
  row, so existing account grants survive a re-apply.
- Apply it with the startup updater, or on the test realm with `make verify-sql`.
- Grant a role to an account:

  ```sql
  DELETE FROM acore_auth.rbac_account_permissions
  WHERE accountId = <id> AND permissionId = 950100 AND realmId = -1;

  INSERT INTO acore_auth.rbac_account_permissions
  (accountId, permissionId, granted, realmId)
  VALUES (<id>, 950100, 1, -1);
  ```

  Or in game: `.rbac account grant <account> 950100`.

- Verify the expanded set before granting. Replace the seed with the role ID:

  ```sql
  WITH RECURSIVE expanded AS (
    SELECT 950100 AS id
    UNION DISTINCT
    SELECT l.linkedId
    FROM acore_auth.rbac_linked_permissions l
    JOIN expanded e ON l.id = e.id
  )
  SELECT COUNT(*) FROM expanded;
  ```

  Expected counts include the role row: support 32, content-tester 27, economy 15, admin 600,
  superadmin 654. These counts are a smoke check, not the contract; review the SQL for the actual
  permission list.

## Testing notes

- `.pinfo <player>` refuses a target with **higher** security. `.mute <player> ...` refuses equal or
  higher security. A `support` account at gmlevel 0 cannot inspect or mute an admin. Use a normal
  player character as the target.
- `.mutehistory <account>` takes an **account name**, not a character name. `.mute` takes a
  character or player name.
- A role grant is not a security-level grant. Target checks still compare GM levels, so the support
  role cannot act on admin characters even when the command permission is granted.

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

## Rules

- No shared GM accounts.
- No `superadmin` for a service account.
- Production RBAC changes are human-only and backed up.
- Test denial, not only success.
- Keep the role matrix in this file current.

## Open work

The five roles were live-tested on the test realm on 2026-11-12. Support, content-tester, economy,
and admin allowed and denied the expected commands. Superadmin was spot-checked with safe commands.
The audit module is still pending, so no audit entries were produced.

## References

- [decisions/ADR-005-gm-tools-and-rbac.md](../../decisions/ADR-005-gm-tools-and-rbac.md)
- [.ai/skills/gm-rbac-management/SKILL.md](../../.ai/skills/gm-rbac-management/SKILL.md)
- [src/server/game/Accounts/RBAC.h](../../src/server/game/Accounts/RBAC.h)
