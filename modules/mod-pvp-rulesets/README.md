# mod-pvp-rulesets

One realm, three per-character PvP modes: **PvE** (default), **War Mode** and **High Risk**.
Implements slice 1 of [RFC-006](../../rfcs/active/RFC-006-pvp-rulesets.md) and
[ADR-033](../../decisions/ADR-033-pvp-rulesets.md).

## Slice 1 scope

- `.pledge pve|warmode|highrisk` and `.pledge status`, server-authoritative.
- Guards: alive, out of combat, in one of ten listed capital cities
  (`PLEDGE_AREAS` in `src/PvpRulesets.h`, faction-checked), not in an
  instance/battleground/arena/battlefield, 5-minute persisted cooldown. The stock
  `AREA_FLAG_CAPITAL` flag is not used: it covers 35 AreaTable rows, including Stormwind Harbor,
  Acherus: The Ebon Hold and every Dalaran sub-area.
- War Mode and High Risk keep a persistent PvP flag, re-asserted at login, on zone change,
  on resurrection and after an unexpected core clear.
- PvE sets no mode flag. The native `/pvp` opt-in stays available.
- Outdoor XP: War Mode +10%, High Risk +15%. No bonus in instances, battlegrounds, arenas,
  battlefields, no-PvP areas or sanctuaries.

Not in this slice: the High Risk death chest, mercenary contract, Outlaw timer, guard and
reaction seams, city service block, kill alerts and the live map feed.

Known slice-1 limit: the client `/pvp` toggle is not refused at the source until the approved
PvP-toggle core seam lands. In War Mode and High Risk an unexpected clear (including a manual
`/pvp` off) is re-asserted after the core's normal timer, not instantly.

## Install

The module is picked up by the normal module build. Apply the SQL:

- `data/sql/custom/db_characters/pvp_rulesets.sql` — per-character mode and cooldown.
- `data/sql/custom/db_auth/pvp_rulesets_command.sql` — RBAC permission `950151` for
  `.pledge`, granted to role 199 (Player Commands).

Copy `conf/PvpRulesets.conf.dist` to `PvpRulesets.conf` in the module config directory and
keep `PvpRulesets.Enable` at the value you want. The tracked `.dist` default is `0`; the local
test realm enables the module in the ignored `env/dist/etc/modules/PvpRulesets.conf`. The
local worldserver applies `data/sql/custom/` on restart.

The module opens its own small pool against `CharacterDatabaseInfo` (one async and one sync
connection) so it can use prepared statements without adding rows to the core statement enum.
A `ModuleDatabasePool` subclass must resize `MySQLConnection::m_stmts` to its statement count
in the connection constructor: `PrepareStatement` indexes that vector directly, and the core
connections are the only ones that do the resize for themselves. The pool and the table probe
run even while the module is disabled, so a character deletion still removes its state row and
a later `.reload config` can enable the module without a restart. Online characters load their
mode at their next login or `.pledge` command. The pool is pinged on the world keep-alive tick
and closed with the core databases.

## State and storage

`mod_pvp_rulesets_state` holds one row per character:

| Column | Meaning |
|--------|---------|
| `mode` | `pve`, `warmode` or `highrisk` |
| `last_toggle` | unix seconds of the last accepted change; drives the cooldown |
| `created_at` | row creation timestamp |

The database row is the truth; there is no aura or client state to trust. A missing row is
PvE. The table is re-appliable and is never dropped by the module; disabling the module
ignores stored modes and leaves the rows for a later re-enable.

## Concurrency

Character state is guarded by one `std::mutex` (`States`). Runtime config values, the table
probe flag and the enabled flag are atomics. No lock is held across a database call, a player
update or a chat send. Hooks that can fire on the map-update thread (`OnPlayerGiveXP`,
`OnPlayerUpdateZone`, `OnPlayerResurrect`, `OnPlayerPVPFlagChange`) only read the map under the
lock; the world-thread paths (login, logout, delete, command) own the writes, so neither can
corrupt the map or block the other.

## Tests

`modules/mod-pvp-rulesets/test/PvpRulesetsTest.cpp` covers mode parsing and names, the
pledge guard order, the ten-area pledge allow-list (faction capitals, neutral hubs, wrong
faction and capital-flagged sub-areas), the cooldown math and the outdoor XP gate. The module
`.cmake` registers the test with the core `unit_tests` target; run `make test`.

## Rollback

Set `PvpRulesets.Enable = 0` and restart. Characters behave as PvE; existing PvP flags clear
through the core's normal timers. The tables stay.
