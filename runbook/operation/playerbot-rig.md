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

If you see a line containing `*:8086`, the rig is ready. If no such line appears, wait one more
minute and check again.

Stop (this closes the rig only, never your game server; do it only when no test is running — a
force-stop in the middle of a test wastes that run):

```bash
pkill -9 -f 'playerbot-rig/env/dist/etc/worldserver.conf'
pkill -9 -f 'playerbot-rig/env/dist/etc/authserver.conf'
```

## Talking to the bots

The bots take orders through the rig's own chat panel. It is already running inside `screen`;
attach to it:

```bash
screen -r ac-pb-worldserver
```

You will see the rig's console (`AC>` prompt). Commands you type there go to the bots. To leave the
panel again: press `Ctrl+A`, then `D`. **Detach only — do not use `Ctrl+A` `K`**, which kills the
rig. Detaching stops nothing; the bots keep working in the background.

## Watching the bots without interrupting them

There are three ways to observe a run, from least to most involved. None of them disturb the run.

### 1. Read the live log (the main way)

In a separate terminal:

```bash
tail -f ~/wow/playerbot-rig/logs/worldserver.log
```

This streams everything the bots say and do as it happens. Useful reading habits:

- Lines starting with `[DC:<botname>]` are that bot's own decisions — "first contact" means it
  spotted a monster, "late joiner" means a monster attacked it, "pull released" means the fight is
  over and the party moves on.
- Lines starting with `TESTRUN` are the run's bookkeeping: doors opened, loot picked up, the run's
  start and end.
- Press `Ctrl+C` to stop reading. That stops only the log display, never the bots.

### 2. Ask the run for status

At the `AC>` prompt (see "Talking to the bots"):

```
.dc test status
```

This answers with the current run: which dungeon, which phase (pulling, clearing a room, fighting a
boss), how many bots are alive, and how long it has been running. `no test runs active` means
everything finished.

### 3. Watch the run with a camera, from inside the game

If you want to *see* it like a movie, log a game client into the rig realm, then at the `AC>`
prompt:

```
.dc test watch
```

A free camera attaches to the party and follows the tank from boss to boss. Keys move the camera
between party members. `watch off` releases the camera. The watcher stays out of the party and
cannot interfere with the fight.

## Monitoring bot behavior in general

Even outside test runs, random bots live in the world and do bot things (wander, level, quest). The
log prints a periodic summary of all of them:

- `Bots engine:` how many are fighting, resting, or dead right now.
- `Bots rpg status:` what each bot's AI is doing (Idle, GoGrind, DoQuest, ...).
- `Bots total quests:` quests accepted/completed/rewarded — this is how you watch bot questing
  health over time.

To follow one specific bot by name through the log:

```bash
grep 'DC:Nurran' ~/wow/playerbot-rig/logs/worldserver.log | tail -20
```

For maximum detail during a run, start it with tracing on:

```
.dc test start deadmines trace=1
```

That prints every decision the party AI makes. The log grows fast; use it when hunting a specific
failure, not for casual watching.

## Running a dungeon test

At the `AC>` prompt:

```
.dc test start deadmines
```

That starts one automated run: five bots (one tank, one healer, three damage) are chosen, geared,
and sent into the dungeon. They clear trash, press the levers and gongs that gate progress, fight
each boss, and loot. You watch the log lines scroll; you do not need to do anything.

Useful dungeon names (short versions work; use `.dc test list` for the complete list):

| Name | Dungeon |
|---|---|
| `deadmines` | The Deadmines |
| `sfk` | Shadowfang Keep |
| `wc` | Wailing Caverns |
| `bfd` | Blackfathom Deeps |
| `stockade` | The Stockade |
| `gnomer` | Gnomeregan |
| `sm-gy`, `sm-lib`, `sm-arm`, `sm-cath` | Scarlet Monastery (Graveyard, Library, Armory, Cathedral) |
| `zf` | Zul'Farrak |
| `brd-db`, `brd-uc` | Blackrock Depths (Detention Block, Upper City) |
| `scholo` | Scholomance |
| `strat` | Stratholme |

### Running many runs at once

One run is an anecdote; a success rate is a measurement. To run a dungeon five times:

```
.dc test plan start pool=deadmines total=5
```

The rig queues five runs of that dungeon and keeps count of successes and failures. Watch with:

```
.dc test status
```

Stop everything (plans and active runs):

```
.dc test stop all
```

You can give more than one dungeon: `pool=deadmines,sfk,wc`.

### After a run

Each run ends with a line like:

```
TESTRUN END tr-20261117-231354-1 result=success reason= bosses=8/8 duration=2057s
```

`result=success` means the party cleared every boss. The dungeon name is on the run's opening line.
`duration` is in seconds (2057s ≈ 34 minutes). If a run fails, the log keeps the reason (which
fight, which creature, what went wrong). Copy the start and end lines into a playtest results file
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
3. Still stuck: `.dc test stop all`, then start a fresh run with a different seed:
   `.dc test start deadmines seed=7` (any number works; different numbers give different random
   parties).
4. Worst case: stop the rig (commands above) and start it again. Nothing is lost except the runs
   that had not finished.
