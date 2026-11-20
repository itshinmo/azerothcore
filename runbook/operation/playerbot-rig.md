# Playerbot test rig — user guide

This page is for running the bot test rig. No engineering knowledge needed: everything is copy-paste
commands and one chat panel.

**Paused 2026-11-19** ([ADR-017](../../decisions/ADR-017-bot-rig-paused.md)). No rig process runs.
The data, traces, ledger, worktree, and binaries are kept. Resume only on the owner's explicit
request; this guide stays current for that day.

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

## Prerequisites and layout

The rig is **not part of this repository** and you do not create it here. It already exists at
`~/wow/playerbot-rig` on this machine. Treat it as a separate, disposable project:

- its own source tree (`core/` with AzerothCore plus `mod-playerbots` and `mod-dungeon-clear`);
- its own build (`build/`), binaries (`env/dist/bin`), configs (`env/dist/etc`), logs (`logs/`);
- its own databases on the same MySQL instance: `acore_pb_auth`, `acore_pb_world`,
  `acore_pb_characters`;
- about 510 bot characters, so a party is always available;
- one client copy, `~/Games/wotlk-test`, already pointed at port 3725.

Do not reuse the local databases, configs, or client copy. Changes in the main
repository never reach the rig until the rig is rebuilt (see “Updating the rig code”).

| Path | What it is |
|---|---|
| `~/wow/playerbot-rig/core/` | rig source tree |
| `~/wow/playerbot-rig/build/` | rig build directory |
| `~/wow/playerbot-rig/env/dist/bin/` | rig binaries |
| `~/wow/playerbot-rig/env/dist/etc/` | rig configs |
| `~/wow/playerbot-rig/logs/` | `authserver.log`, `worldserver.log` |
| `~/wow/playerbot-rig/env/dist/bin/Server.log` | worldserver appender log |
| `~/wow/playerbot-rig/env/dist/bin/dc_testruns.jsonl` | one JSON record per finished dungeon run |
| `~/wow/playerbot-rig/env/dist/bin/dc_testplans.jsonl` | plan summaries, written when a plan ends |
| `~/wow/playerbot-rig/env/dist/bin/dc_testrun_live.json` | live dashboard snapshot |
| `~/wow/playerbot-rig/env/dist/bin/lab_traces/` | trace files from runs started with `trace=1` |

## Ready checklist

Before starting a run, confirm all four:

```bash
lsof -nP -iTCP:3725 -sTCP:LISTEN | tail -1     # login port
lsof -nP -iTCP:8086 -sTCP:LISTEN | tail -1     # world port
grep -a 'worldserver-daemon) ready' ~/wow/playerbot-rig/logs/worldserver.log | tail -1
mysql -h 127.0.0.1 -u <user> -p -N \
  -e "SELECT name,address,port,flag FROM acore_pb_auth.realmlist;"
```

The realm row must show `127.0.0.1`, port `8086`, flag `0`.

## Starting and stopping the rig

Open Terminal. Paste one line at a time.

Start:

```bash
R=~/wow/playerbot-rig
cd "$R/env/dist/bin"
screen -wipe
screen -dmS ac-pb-authserver bash -c "cd '$R/env/dist/bin' && exec stdbuf -oL -eL ./authserver -c '$R/env/dist/etc/authserver.conf' >>'$R/logs/authserver.log' 2>&1"
sleep 2
screen -dmS ac-pb-worldserver bash -c "cd '$R/env/dist/bin' && exec stdbuf -oL -eL ./worldserver -c '$R/env/dist/etc/worldserver.conf' >>'$R/logs/worldserver.log' 2>&1"
```

`stdbuf` keeps the authserver log readable; without it the startup lines, including the realm port,
can sit in the process buffer for hours. `screen -wipe` removes dead sessions left by an earlier
stop, so the new session is the only one with the rig's name.

Wait about three minutes. Then check it is up:

```bash
lsof -nP -iTCP:8086 -sTCP:LISTEN | tail -1
```

If you see a line containing `*:8086`, the rig is ready. If no such line appears, wait one more
minute and check again.

The authserver marks every realm offline when it boots; the worldserver clears that bit for its own
realm only at its own startup. The start order above (authserver first, worldserver last) therefore
works. If you restart the authserver by itself, the realm goes offline again — clear the bit after
the restart:

```bash
mysql -h 127.0.0.1 -u <user> -p -e "UPDATE acore_pb_auth.realmlist SET flag=0, port=8086 WHERE id=1;"
```

If selecting the realm reopens the realm list, read the authserver log first. It prints
`Added realm "AzerothCore" at 127.0.0.1:<port>` at startup. A line with `8085` means an older
authserver is still holding port 3725 and serving a realm list cached before the rig started; stop
every authserver process, start one fresh, and confirm the log now says `8086`.

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

`screen -ls` on macOS can report "No Sockets found" even while the rig runs, because the sockets
live in a per-session temporary directory. Prefix any `screen` command with that directory when the
plain form cannot see the sessions:

```bash
export SCREENDIR=/private/var/folders/n0/qhyplrb17tq7gmrfy0v4f_3h0000gn/T/.screen
```

A command can also be sent without attaching, which is how scripted batches are driven:

```bash
screen -S ac-pb-worldserver -X stuff "$(printf '%s\r' '.dc test status')"
```

Send a real carriage return (`\r`). A literal `\n` is typed into the console as the two characters
backslash and n, and nothing runs.

`screen -X stuff` can silently do nothing against a freshly detached session. If a command never
appears in the log, drive an attach instead. macOS ships `expect`; this sends one command and
detaches safely:

```bash
expect -c '
set timeout 30
spawn env SCREENDIR=/private/var/folders/n0/qhyplrb17tq7gmrfy0v4f_3h0000gn/T/.screen screen -r ac-pb-worldserver
sleep 2
send -- ".dc test status\r"
sleep 3
send -- "\001d"
expect eof
'
```

`\001d` is `Ctrl+A` then `D`, the detach sequence. Never send `Ctrl+A` `K`; that kills the rig.

The rig's database is `acore_pb_auth` / `acore_pb_world` / `acore_pb_characters` on the same MySQL
instance; the realm row in `acore_pb_auth.realmlist` must carry the rig's world port, `8086`. A
realm row left on `8085` makes the client return to the realm list after selection.

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

### 3. See the run in game, live (the camera)

The rig can render the dungeon run in your game client, like watching a replay live. The watcher is
invisible to the monsters and cannot change the fight — a pure camera.

One-time setup:

1. **Make a spare copy of the game client.** Copy your whole client folder to a second location.
   Your normal copy keeps pointing at the real server and stays untouched. This machine already has
   one at `~/Games/wotlk-test`.
2. **Point the spare copy at the rig.** In the spare copy's folder, open `Data/enUS/realmlist.wtf`
   with a text editor and make its active line read:

   ```
   set realmlist 127.0.0.1:3725
   ```

   Keep `libSiliconPatch` off in that copy: leave `#mods/libSiliconPatch.dll` commented out in
   `dlls.txt`. The patch breaks the client's water handling; see
   [stormwind-water.md](../troubleshooting/stormwind-water.md).

3. **Use the rig's watcher account.** The rig already has an `ADMIN` account at GM level 3 with
   character `Asdaddsa`; log in with it. A separate watcher account is optional; create one at the
   rig's `AC>` prompt (see "Talking to the bots") and give it GM level 3:

   ```
   .account create mohsen choose-your-password
   .account set gmlevel mohsen 3 1
   ```

   The GM level is what lets the camera command work. These accounts exist only on the rig; they are
   not your game-server accounts. If an account was created through this console, its password
   appeared in the rig log in plain text; set a fresh one with
   `.account set password <name> <old> <new>`.

4. **Log into the rig** with that account in the spare client and create any character (any race
   and class; level 1 is fine). You will see the rig's world — possibly full of random bots going
   about their day.

During a run, type in the game's **chat box** — not the `AC>` prompt, the camera command only works
in-game:

```
.dc test watch
```

A free camera attaches to the party and follows the tank from boss to boss. Useful while watching:

- `.dc spectate next` / `.dc spectate prev` — move the camera between party members.
- `.dc test watch off` — release the camera.
- `.dc test status` — typed in the game chat as well; shows the run's phase.

You are a ghost to the fight: monsters cannot see the watcher, and nothing you do changes the
outcome. Keep the `AC>` prompt for starting and managing runs only.

Why this cannot disturb the run: the camera is a spectator spell, not a party member. The watcher
body is parked at the dungeon entrance and the camera works through a scrying effect, so the combat
AI never counts you in pulls, threat, or loot.

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

Every run already streams the party's decisions to the log (the `[DC:<bot>]` lines above). If you
want a deeper record for failure analysis, start the run with:

```
.dc test start deadmines trace=1
```

That records a machine-readable trace file (saved inside the rig folder at
`~/wow/playerbot-rig/env/dist/bin/lab_traces/`) which is scored
when the run ends. You will not see extra log lines while it runs — the value is in the end-of-run
analysis. Use it when hunting a specific failure, not for casual watching.

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
| `mc`, `ony`, `bwl`, `zg`, `aq20`, `aq40` | Classic raids |
| `gruul`, `kara`, `kara-chess` | TBC raids; `kara-chess` is the Karazhan chess scenario slice |

Raids launch at the catalogue default of 10 bots. A failed raid gets one rerun at its map cap
before it counts as a finding: 40 for `mc`, `bwl`, `aq40`; 20 for `zg`, `aq20`; 25 for `gruul`;
10 for `ony`, `kara`, `kara-chess`.

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

### Running dungeons in parallel

Runs are not serial. A plan keeps several parties in flight at once, up to `concurrent=N`:

```
.dc test plan start pool=deadmines,sfk,wc total=12 concurrent=3
```

Omitted, `concurrent` defaults to 5. The server accepts any number; the real ceiling is the machine
and the free bot pool. On the MacBook rig, 4 parties run comfortably beside the game client; raise
it only while watching the CPU. Retune a live plan without stopping it:

```
.dc test plan edit <planId> concurrent=5
```

`pick=bag` (the default) gives every dungeon in the pool one run per cycle, in shuffled order. A
pool of 27 dungeons with `total=27` therefore covers each dungeon exactly once, whatever order the
bag draws. That is how a whole expansion is swept in one batch:

```
.dc test plan start pool=rfc,wc,stockade,bfd,rfk,sm-gy,gnomer,sm-lib,sm-arm,sm-cath,rfd,uldaman,zf,maraudon,mara-orange,mara-purple,mara-pw,st,brd-db,brd-uc,lbrs,ubrs,dm-east,dm-west,dm-north,scholo,strat total=27 concurrent=4 pick=bag
```

The bag order mixes levels on purpose; do not read the launch order as a difficulty order.

With several runs live, the bare `.dc test watch` is refused because the camera needs one target.
Watch a specific run by its dungeon token, which also works when the same dungeon runs twice:

```
.dc test watch strat
```

Each run's `TESTRUN START` and `TESTRUN END` lines carry the run id; select by run id when tokens
are ambiguous. Per-run records accumulate in
`~/wow/playerbot-rig/env/dist/bin/dc_testruns.jsonl`, plan summaries in `dc_testplans.jsonl` next to
it, and one summary line per finished run is all the ledger needs.

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

## Reading the result files

The log is the live view; the files are the record.

```bash
B=~/wow/playerbot-rig/env/dist/bin
tail -n 5 "$B/dc_testruns.jsonl"          # finished runs, one JSON object per line
cat "$B/dc_testplans.jsonl"               # plan summaries, one line per finished plan
ls -la "$B/lab_traces"                    # traces from runs started with trace=1
```

Each finished run keeps its run id, dungeon, seed, level, result, bosses, duration, comp, pull
statistics, and diagnostics. The seed makes a run exactly replayable:
`.dc test start <dungeon> seed=<seed>`. Add `trace=1` to write a machine-readable trace for failure
analysis. A trace file can be large (tens of MB); use it for a specific failure, not for every run.

## Updating the rig code

The rig is its own checkout. After changing a rig module (for example `mod-dungeon-clear`):

```bash
cd ~/wow/playerbot-rig
cmake --build build -j4
cmake --install build
cp build/src/server/apps/worldserver env/dist/bin/worldserver
```

The install prefix in the rig's CMake cache is `env`, not `env/dist`, so the last copy is required
for the start command above to run the new binary. Keep the previous binary as
`env/dist/bin/worldserver.pre-<date>` when testing a harness change, so a bad build can be rolled
back. Restart the rig after installing; the running process keeps the old binary.

## Reading failures without panicking

A failed run is a **finding, not a disaster**. The rig exists to find broken content on purpose. A
failure usually names the creature (for example `Defias Overseer, entry 634`). Note the entry
number and the dungeon; that is all the next fix needs.

## What the bots will never do

- They never touch the real server's databases, characters, or items.
- They never appear in the real game world.
- They never replace a human check of "does this quest play right" — bots prove a dungeon can be
  completed; a human still judges the experience.

## Harness behaviour notes (2026-11-18, Blackfathom Deeps)

The rig's harness was patched during the classic sweep. Current behaviour you can rely on:

- The no-progress clock is held once every roster boss is credited, so the final loot hold cannot
  lose to the watchdog.
- Combat progress is sampled across the whole party, not only the tank.
- A swim step that reads "off the authored polyline" replans with `SwimPathfinder` from the live
  position instead of abandoning. A genuine teleport still abandons.
- The Portal of Aku'mai (`21117`) is navigation-ignored: it is never treated as a corridor blocker
  and never auto-pauses a run.

Two defects remain open in BFD; a run there can still end early:

1. **Empty-path livelock.** Standing on the fires anchor, advance rebuilds a zero-segment path every
   tick (`path rebuilt ... segs=0` + `reaching end of path polyline`) and never yields to the fires
   objective. The log grows fast and the CPU sits near half a core.
2. **Wave gate starvation.** After the third fire, the Barbed Crustacean wave is not pulled; the
   party stands out of combat and the fourth fire is never clicked.

If a BFD run stops after three fires, that is these two defects, not a content bug. Stop it with
`.dc test stop` rather than waiting for the timeout.

## Debugging a player report with the rig

Dungeons are assumed to work until a player reports one ([ADR-016](../../decisions/ADR-016-bot-driven-verification.md)).
A report is the trigger to run that dungeon again:

1. Map the report to a token (table above) and start one run: `.dc test start <dungeon>`.
2. If the report names a repeatable spot or failure, run it with `trace=1` for the end-of-run
   analysis. Every run's seed is in `dc_testruns.jsonl`; `.dc test start <dungeon> seed=<seed>`
   replays it exactly.
3. Read the failure as a finding: note the creature or gameobject entry, the dungeon, and the
   decisive log lines.
4. Record the run in the [ledger](../audits/2026-11-17-bot-dungeon-runs.md) under a "Player report"
   row, with the report reference.
5. Fix the cause in the right place: content in `data/sql` in this repository, harness defects in
   the rig only. Replay the same seed before calling it fixed.

## If the client returns to the realm list

Login works, the realm list opens, and picking the realm reopens it. That is the client failing to
reach the rig's world port after the realm row gave it an address. Check the row:

```bash
mysql -h 127.0.0.1 -u <user> -p -e "SELECT name, address, port, flag FROM acore_pb_auth.realmlist;"
```

`port` must be `8086` (the rig's world port, not the main server's `8085`) and `flag` must be `0`.
Fix a wrong row with `UPDATE acore_pb_auth.realmlist SET port=8086 WHERE id=1;` then **restart the
authserver** so it re-reads the table; a stale process can keep advertising 8085 even though
`RealmsStateUpdateDelay` reloads the row every 20s. The authserver's boot marks the realm offline,
so clear the bit after the restart, and confirm the log says
`Added realm "AzerothCore" at 127.0.0.1:8086`:

```bash
UPDATE acore_pb_auth.realmlist SET flag=0 WHERE id=1;
```

If `lsof -nP -iTCP:8086 -sTCP:LISTEN` shows no listener, the worldserver is down and that is the real
cause.

## If something looks stuck

1. Check the console: `.dc test status` tells you what the current run is doing.
2. Give a stuck run five minutes; some fights have long phases.
3. Still stuck: `.dc test stop all`, then start a fresh run with a different seed:
   `.dc test start deadmines seed=7` (any number works; different numbers give different random
   parties).
4. Worst case: stop the rig (commands above) and start it again. Nothing is lost except the runs
   that had not finished.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `screen -ls` says “No Sockets found” | screen uses a per-session socket directory | `export SCREENDIR=/private/var/folders/n0/qhyplrb17tq7gmrfy0v4f_3h0000gn/T/.screen` |
| Commands typed via `screen -X stuff` never run | a fresh detached session can ignore `stuff` | drive an attach with `expect`, see “Talking to the bots” |
| Authserver log says `Could not bind to 0.0.0.0:3725` | an older authserver still owns the port | `pkill -9 -f 'playerbot-rig/env/dist/etc/authserver.conf'`, `screen -wipe`, start again |
| Realm list reopens after selection | stale authserver advertising 8085, or realm flag 2 | fix `acore_pb_auth.realmlist` to `port=8086, flag=0`, restart authserver, confirm its log says 8086 |
| Ports stay bound after `pkill -TERM` | bots take ~30s to log out | wait, then `pkill -9`; check with `lsof -nP -iTCP:8086 -sTCP:LISTEN` |
| `Previous session did not shut down cleanly` at startup | the previous worldserver was force-stopped | expected after a kill; no action |
| A plan seems stuck at a low count | `.dc test status` was read from an old console frame | resend it; check `TESTPLAN ... launched` and `TESTRUN END` lines in the log |
| Run refuses to start | unknown token, no free bot for a comp slot, or a character busy | `.dc test list`; wait; retry |
| Bots stop following commands | the driver character name is case-sensitive | rig config must say `Dcdriver`, not `dcdriver` |
| Machine becomes sluggish | too many parties or a local build running | keep 5–8 parties; reduce with `.dc test plan edit <planId> concurrent=N` |
