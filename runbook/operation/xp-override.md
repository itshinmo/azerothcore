# Experience override

## When to use

A player asks to level at 1x, or a GM needs to explain or verify the per-account experience opt-in
provided by `modules/mod-xp-override`. The player toggles it themselves with `.xp`; there is no GM
command for it.

## Prerequisites

- `data/sql/custom/db_auth/account_xp_override.sql` applied. The world command row in
  `xp_override_command.sql` is optional: it only supplies `.help xp` text.
- `mod-xp-override` built into the worldserver.
- The player is in game on the account to change.

## Steps

1. The player types `.xp` with no arguments.
2. Read the confirmation:
   - `Experience override enabled: 1x.` means the account now earns base 1x experience.
   - `Experience override removed. This account now uses the realm default.` means the realm
     rate applies again.
3. The change is immediate for the current session and persists across logins.

The intended default is 3x (ADR-012). The module reads the live `Rate.XP.*` values at award time.

## Verification

The row lives in the auth database:

```sql
SELECT account_id, created_at
FROM acore_auth.account_xp_override
WHERE account_id = <account id>;
```

A row means 1x; no row means the realm default. The in-game confirmation is the authoritative
check for the player.

To verify the applied amount, kill one creature of the same level with and without the override
on a test realm and compare the experience gain. See `modules/mod-xp-override/README.md` for the
sources that are adjusted.

## Troubleshooting

- `Could not save the experience override. Try again later.` — the synchronous auth database write
  failed. Check the worldserver log and that the table exists; the cache was not changed.
- An unknown-command error means the module is not loaded. A missing `command` row only removes the
  `.help xp` text; it does not disable the command.
- Pet experience follows the reduced kill value; that is expected, not a bug.
- Scripted `GiveXP` calls stay at the realm rate; they bypass `OnPlayerGiveXP`.

## Escalation

If the table is missing, applying the SQL fails, or the override does not survive relog, follow
`runbook/troubleshooting/database-errors.md` and record the account id, character, time, and log
excerpt. Do not edit player rows by hand outside a documented support action.

## References

- `modules/mod-xp-override/README.md`
- `decisions/ADR-012-progression-rates.md`
- `runbook/operation/apply-sql-update.md`
