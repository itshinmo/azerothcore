# Playerbot test rig — user guide

This page is for running the bot test rig. No engineering knowledge needed: everything is copy-paste
commands and one chat panel.

## What this is

The rig is a **second, private copy of the game** that lives next to your real server. Its only job
is testing: robot players ("bots") log into it, group up, and run dungeons on their own while a
computer reads what happens. It can never touch your real server, your characters, or your items —
it runs on separate ports and separate databases.

The bots are not part of the game you play. Players never see them.

## Before you start: two servers exist

| | Your game server | The test rig |
|---|---|---|
| Where | `make start` / `make stop` in the main folder | `~/wow/playerbot-rig` (see below) |
| Game port | 8085 | 8086 |
| Login port | 3724 | 3725 |
| Purpose | Playing | Automated testing |

Rule: they run at the same time without problems, because every port and database is different.

## Starting and stopping the rig

Open Terminal. Paste one line at a time.

Start:

```bash
R=~/wow/playerbot-rig
cd "$R/env/dist/bin"
screen -dmS ac-pb-authserver bash -c "cd '$R/env/dist/bin' && ./authserver -c '$R/env/dist/etc/authserver.conf' >>'$R/logs/authserver.log' 2>&1"
sleep 2
screen -dmS ac-pb-worldserver bash -c "cd '$R/env/dist/bin' && ./worldserver -c '$R/env/dist/etc/worldserver.conf' >>'$R/logs/worldserver.log' 2>&1"
```

Wait about three minutes. Then check it is up:

```bash
lsof -nP -iTCP:8086 -sTCP:LISTEN | tail -1
```

If you see a line ending in `:8086`, the rig is ready. If the line is missing, wait one more minute
and check again.

Stop (this closes the rig only, never your game server):

```bash
screen -S ac-pb-worldserver -X stuff "$(/bin/echo -e '')"; pkill -9 -f 'playerbot-rig/env/dist/bin/worldserver'; pkill -9 -f 'playerbot-rig/env/dist/bin/authserver'
```

(Do this only when no test is running — a force-stop in the middle of a test wastes that run.)

## Talking to the bots

The bots take orders through the rig's own chat panel. It is already running inside `screen`;
attach to it:

```bash
screen -r ac-pb-worldserver
```

You will see the rig's console (`AC>` prompt). Commands you type there go to the bots. To leave the
panel again: press `Ctrl+A`, then `K`, then confirm with `y`. Leaving does not stop anything.

## Running a dungeon test

At the `AC>` prompt:

```
.dc test start deadmines
```

That starts one automated run: five bots (one tank, one healer, three damage) are chosen, geared,
and sent into the dungeon. They clear trash, press the levers and gongs that gate progress, fight
each boss, and loot. You watch the log lines scroll; you do not need to do anything.

Useful dungeon names (short versions work):

| Name | Dungeon |
|---|---|
| `deadmines` | The Deadmines |
| `sfk` | Shadowfang Keep |
| `wc` | Wailing Caverns |
| `bfd` | Blackfathom Deeps |
| `stocks` | The Stockade |
| `gnomer` | Gnomeregan |
| `sm` | Scarlet Monastery |
| `zf` | Zul'Farrak |
| `brd` | Blackrock Depths |
| `scholo` | Scholomance |
| `strat` | Stratholme |

(The full list: `.dc test list` shows every dungeon the rig knows, with its map and level.)

### Running many runs at once

One run is an anecdote; a success rate is a measurement. To run a dungeon five times:

```
.dc test plan start pool=deadmines total=5
```

The rig queues five runs of that dungeon and keeps count of successes and failures. Watch with:

```
.dc test status
```

Stop the plan:

```
.dc test stop
```

You can give more than one dungeon: `pool=deadmines,sfk,wc`.

### After a run

Each run ends with a clear result in the console: the dungeon, whether the party wiped or cleared,
and how long it took. If a run fails, the log keeps the reason (which fight, which creature, what
went wrong). Copy the result lines into a playtest results file
(`runbook/audits/<date>-base-game-playtest.md` in the main project folder) — failures there become
fixes in the real server.

## Reading failures without panicking

A failed run is a **finding, not a disaster**. The rig exists to find broken content on purpose. A
failure usually names the creature (for example `Defias Overseer, entry 634`). Note the entry
number and the dungeon; that is all the next fix needs.

## What the bots will never do

- They never touch the real server's databases, characters, or items.
- They never appear in the real game world.
- They never replace a human check of "does this quest play right" — bots prove a dungeon can be
  completed; a human still judges the experience.

## If something looks stuck

1. Check the console: `.dc test status` tells you what the current run is doing.
2. Give a stuck run five minutes; some fights have long phases.
3. Still stuck: `.dc test stop`, then start a fresh run with a different seed:
   `.dc test start deadmines seed=7` (any number works; different numbers give different random
   parties).
4. Worst case: stop the rig (commands above) and start it again. Nothing is lost except the runs
   that had not finished.
