# mod-xp-override

Lets a player toggle their own account between 1x experience and the realm default with `.xp`.

## Behavior

- `.xp` has no arguments and takes effect immediately.
- No override row for the account: the command inserts one and the account earns 1x experience.
- Override row present: the command deletes it and the account returns to the realm default.
- The command has a 5 second per-account cooldown. It rejects an earlier toggle with a wait message.
- Only the calling account is affected. There is no target argument and no GM bypass.
- Login loads the account state from the auth database into an in-memory cache. The toggle updates
  the cache immediately. Account deletion removes the row and the cache entry. All hooks and the
  command run on the world thread.

The confirmation names the resulting state: `1x` or the realm default.

The insert is idempotent (`ON DUPLICATE KEY UPDATE`), so an existing row enables the override instead
of failing. The write runs synchronously on the world thread and the 5 second cooldown bounds it. On
a database error the command reports the failure and leaves the cache unchanged.

## Experience sources

`PlayerScript::OnPlayerGiveXP` divides the incoming amount by the configured realm rate:

| Source | Rate |
|--------|------|
| `XPSOURCE_KILL`, not in a battleground | `Rate.XP.Kill` |
| `XPSOURCE_KILL`, Alterac Valley (map 30) | `Rate.XP.BattlegroundKillAV` |
| `XPSOURCE_KILL`, Warsong Gulch (map 489) | `Rate.XP.BattlegroundKillWSG` |
| `XPSOURCE_KILL`, Arathi Basin (map 529) | `Rate.XP.BattlegroundKillAB` |
| `XPSOURCE_KILL`, Eye of the Storm (map 566) | `Rate.XP.BattlegroundKillEOTS` |
| `XPSOURCE_KILL`, Strand of the Ancients (map 607) | `Rate.XP.BattlegroundKillSOTA` |
| `XPSOURCE_KILL`, Isle of Conquest (map 628) | `Rate.XP.BattlegroundKillIC` |
| `XPSOURCE_QUEST` | `Rate.XP.Quest` |
| `XPSOURCE_QUEST_DF` | `Rate.XP.Quest.DF` |
| `XPSOURCE_EXPLORE` | `Rate.XP.Explore` |
| `XPSOURCE_BATTLEGROUND` | `Rate.XP.BattlegroundBonus` |

The core applies the rate before the hook, so dividing by it removes the realm rate and keeps the
content and player multipliers. The result is rounded to the nearest integer and never drops below 1
for a positive amount. A rate of zero or less disables the source; the amount is left unchanged. A
kill inside a battleground map that is not one of the six recognised maps returns no rate and the
gain is not adjusted.

## SQL

Apply both files before enabling the module:

- `data/sql/custom/db_auth/account_xp_override.sql` creates `account_xp_override` in the auth
  database. One row per account, primary key `account_id`, `created_at` timestamp.
- `data/sql/custom/db_world/xp_override_command.sql` writes the `command` row for `.help xp`. The
  command is security 0 and needs no RBAC permission. The row supplies help text only; the command
  works without it.

The startup updater applies `data/sql/custom/` when `updates_include` contains `custom/db_*`. For a
manual apply, see `runbook/operation/apply-sql-update.md`.

## Configuration assumptions

- The realm default is the set of `Rate.XP.*` keys above; the module reads them with
  `sWorld->getRate(...)` at award time, so a live rate change applies without a restart.
- ADR-012 sets the intended default to 3x. Other rates, including values below 1, are supported.

## Scope and limits

- Adjusted player XP sources: kill (including the per-map battleground kill rate), quest, quest
  Dungeon Finder reward, exploration, and the battleground bonus award.
- Pet XP follows the reduced kill value: `KillRewarder` awards pet XP from the same amount that the
  hook adjusted.
- Direct `Player::GiveXP` calls from scripts do not pass through `OnPlayerGiveXP` and are not
  adjusted.
- No offline or cross-realm UI: the command needs an in-game session. A GM changing rows by hand
  affects the account at its next login.
- One override covers the whole account, not a single character.
