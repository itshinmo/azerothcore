# Bug reports

Players file bugs and suggestions from the game client's report UI. The core stores them in
`acore_characters.bugreport` — no chat command, no GM surface, no config. This page is the triage
procedure around that table.

## How players report

- In the 3.3.5 client, use the built-in bug/suggestion UI (the Help/`?` menu). The client requires
  a category before submission and confirms with "Bug submitted" (client strings
  `BUG_CATEGORY_ERROR` / `BUG_SUBMITTED`).
- There is no in-game command to list or follow up on a report. Players should include the
  character name, location, and time in the text — the table does not store them.

## How it is stored

- Submission is the `CMSG_BUG` packet (`src/server/game/Handlers/MiscHandler.cpp`); only
  `type` (client-chosen category string) and `content` (free text) are stored
  (`CHAR_INS_BUG_REPORT`). The packet's bug-vs-suggestion flag is read and discarded.
- Table `acore_characters.bugreport`: `id`, `type`, `content`, plus fork additions `State`
  (default `1`), `Assignee`, `Comment`. Core writes `type` and `content` only; `State`, `Assignee`,
  and `Comment` are ours to manage by hand.

Known limitations: reports cannot be attributed to a player, location, or time; there is no rate
limit or size check on the packet, so spam and oversized text are possible; `type` is free text.
Triage accordingly — do not build systems on the category string.

## Triage

Query the backlog (State `1` = new):

```sql
SELECT id, type, LEFT(content, 120)
FROM acore_characters.bugreport
WHERE State = 1
ORDER BY id;
```

Work each report through this lifecycle with `State`: `1` new, `2` accepted, `3` rejected
(duplicate, works as intended, or spam), `4` fixed — by a data fix, a core/module fix, or an
upstream merge.

```sql
-- claim it
UPDATE acore_characters.bugreport SET State = 2, Assignee = '<name>' WHERE id = <id>;
-- annotate the outcome
UPDATE acore_characters.bugreport SET Comment = '<what was done>' WHERE id = <id>;
UPDATE acore_characters.bugreport SET State = 4 WHERE id = <id>;
```

Rejected or fixed reports stay in the table; deleting is reserved for spam floods.

## From report to fix

1. Reproduce in the client. Note the location with `.gps` and the map id — dungeon findings also
   feed the [base-game checklist](base-game-verification.md).
2. Data-level cause: fix in `data/sql/updates/pending_db_*/` (or `custom/` per
   [apply-sql-update.md](apply-sql-update.md)); a duplicate of something upstream already fixed
   needs no local change.
3. Code-level cause: check upstream `master` first — the weekly sync may already carry the fix.
   Unique fixes are upstream candidates: a clean upstream PR keeps the firehose working for us.
4. Close the loop: set `State = 4` with a `Comment` naming the fix (commit, SQL file, or upstream
   issue).
