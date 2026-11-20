# Environment overview — start here

## When to use

First day in this repository, or when you need to remember which environment you are supposed to use.
Read this before the build or operation runbooks. It explains the whole machine at a glance: what the
project is, what runs where, and which environment belongs to which task.

## What this repository is

This is a private-server fork of [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk): a
C++20 emulator for World of Warcraft 3.3.5a (Wrath of the Lich King). Two programs do the work:

- `authserver` — accepts the client login, checks the account, and returns the realm list.
- `worldserver` — runs the game world: maps, creatures, quests, spells, players.

Both talk to one MySQL instance. Game content comes from the world database plus the client data
files under `DataDir` (`dbc/`, `maps/`, `vmaps/`, `mmaps/`). The client connects with `realmlist.wtf`.

The project is not upstream AzerothCore. Project rules live in [AGENTS.md](../../AGENTS.md), current
state in [.ai/memories/status.md](../../.ai/memories/status.md), and procedures in
[runbook/](../README.md). New game content is out of scope until the base game passes its Phase 1
gate (ADR-013).

## The three environments

They can run at the same time because every port and database is different. Never point one
environment's client at another environment's ports.

| | Local (development) | Bot rig |
|---|---|---|
| Purpose | Normal play, manual testing, GM API | Automated playerbot dungeon runs |
| Directory | this checkout | `~/wow/playerbot-rig` (outside the repo) |
| Auth port | 3724 | 3725 |
| World port | 8085 | 8086 |
| GM API port | 8090 | not installed |
| Databases | `acore_auth`, `acore_characters`, `acore_world` | `acore_pb_auth`, `acore_pb_characters`, `acore_pb_world` |
| Client copy | `~/Games/wotlk-clean` (the modernized bundle client, launched via WoWSilicon; see [client-bundle.md](../operation/client-bundle.md)) | `~/Games/wotlk-test` (already points at 3725) |
| Start with | `make start` | manual `screen` commands, see [playerbot-rig.md](../operation/playerbot-rig.md) |

Warnings:

- The bot rig is a **separate checkout and build**. Changes in this repository do not reach it until
  the rig is rebuilt.
- The bot rig's databases are disposable copies. Playerbot runs never touch the local characters.

## How the pieces fit

```text
game client
    |  login (3724 / 3725)
    v
authserver ---- MySQL: accounts, realmlist, bans, session keys
    |  realm list (world port + address)
    v
worldserver --- MySQL: world content, characters, creature state
    |  reads DataDir: dbc, maps, vmaps, mmaps
    v
game world
```

The worldserver is the slow part to start: it loads maps, scripts, and modules, then writes
`WORLD: World Initialized` and `worldserver-daemon) ready` to its log. Give it one to three minutes.

## First day, in order

1. Install prerequisites and build: [setup-macos.md](setup-macos.md).
2. Create the three databases: [database-bootstrap.md](database-bootstrap.md).
3. Check the machine with `make doctor`. It verifies binaries, config, database, client data, ports,
   pending SQL, logs, and disk.
4. Start the local stack with `make start`, then `make status` and `make logs`.
5. Create your GM account at the worldserver console (`.account create`, then `.account set gmlevel`
   as described in the setup runbook), and log in with the client copy pointed at `127.0.0.1`.
6. Get oriented with [commands.md](commands.md) and [worktrees-and-branches.md](worktrees-and-branches.md).
7. Only if you are running bot tests: read [playerbot-rig.md](../operation/playerbot-rig.md).

A healthy local start looks like this:

- `lsof -nP -iTCP:3724 -sTCP:LISTEN` and `-iTCP:8085` both return a line.
- `env/dist/logs/Errors.log` has no new startup errors.
- The client reaches the realm list, and the realm is not marked offline.
- A GM character can run `.server info`.

## Which environment should I use?

| Task | Environment |
|---|---|
| Write code, run unit tests | Local build only; no server needed |
| Play the game and check behavior | Local |
| GM commands, addon, GM API | Local |
| Risky SQL checks | Local, after a backup (lint first; ADR-018) |
| Live e2e | Dormant until the launch `dev`/`ptr` realms (ADR-018) |
| Automated dungeon/quest verification | Bot rig |
| Content audits and exports | Local database, read-only |

## Playing on the LAN with a friend

The local stack is the LAN realm; do not start a third one. The rig is already separate on
3725/8086, so both can run at once.

1. Find this Mac's LAN address and mask:

   ```bash
   ipconfig getifaddr en0
   ifconfig en0 | grep 'inet '
   ```

2. Point the realm at it. Keep `address` on loopback so this Mac still connects locally; put the
   LAN IP in `localAddress`:

   ```sql
   UPDATE acore_auth.realmlist
   SET address = '127.0.0.1',
       localAddress = '<LAN-IP>',
       localSubnetMask = '<LAN-MASK>',
       port = 8085,
       flag = 0
   WHERE id = 1;
   ```

   `Realm::GetAddressForClient` then returns `127.0.0.1` to a client on this Mac and the LAN IP to
   a client inside the subnet. If the friend is on a different subnet, set `address` to the LAN IP
   as well.

3. Start the stack (`make start`) and create an account for the friend at the console:

   ```text
   .account create friendname theirpassword
   ```

   Account names are stored upper-cased. No GM level is needed to play.

4. On the friend's client, in `Data/enUS/realmlist.wtf`:

   ```text
   set realmlist <LAN-IP>:3724
   ```

   Client must be 3.3.5a build 12340. Test reachability first with `nc -vz <LAN-IP> 3724` from their
   machine; if that fails, the router or Wi-Fi client isolation is the cause, not the server.

Rules:

- **Never run a second worldserver against `acore_characters`.** Local uses `acore_*`, the rig uses
  `acore_pb_*`; a third worldserver on either character DB can corrupt characters.
- Keep the GM API on `127.0.0.1:8090`. It is not a LAN service.
- DHCP can move the LAN IP; reserve it or re-check before each session.
- If the macOS firewall is enabled, allow incoming connections for `worldserver` and `authserver`.

## Where things live

| Path | Contents |
|---|---|
| `build/` | normal build, ignored |
| `build-verify/` | tests and `-Werror` build, ignored |
| `env/dist/bin`, `env/dist/etc`, `env/dist/logs` | local install: binaries, live configs, logs, ignored |
| `src/` | C++ source |
| `data/sql/` | schema, updates, custom project SQL |
| `modules/` | project and external modules |
| `tools/dev/` | `make` wrappers, doctor, backup, server control |
| `runbook/` | procedures (this file lives here) |
| `specs/`, `decisions/`, `rfcs/` | contracts, decisions, proposals |

## First failures to expect

| Symptom | Usual cause | Check |
|---|---|---|
| `Address already in use` | Another stack or an old process owns the port | `lsof -nP -iTCP:<port> -sTCP:LISTEN`, then stop the right stack |
| Client returns to the realm list after selecting a realm | Realm list advertises the wrong world port, or the realm is flagged offline | authserver log `Added realm ...`; `realmlist.port` and `flag` |
| `Could not connect to MySQL` | MySQL not running, or wrong host/user/password in config | `mysql -h 127.0.0.1 -u acore -p -e 'SELECT 1'` |
| Worldserver starts without maps | `DataDir` wrong or missing `maps/` `vmaps/` `mmaps/` | `make doctor`, [map-data-missing.md](../troubleshooting/map-data-missing.md) |
| Empty character list | Wrong account, or characters belong to another realm/database | `acore_characters.characters` for that account |
| Bots log in but the run never starts | Rig console input or a stale rig authserver | [playerbot-rig.md](../operation/playerbot-rig.md#troubleshooting) |

## Safety for a new developer

- Never commit credentials, database passwords, tokens, or player data. Live configs under
  `env/dist/etc/` are ignored; templates end in `.dist`.
- Back up the three databases before any write batch: `make backup`.
- Never edit `data/sql/base/`, `data/sql/archive/`, or `data/sql/updates/db_*/`. Use
  `data/sql/updates/pending_db_*/` or `data/sql/custom/db_*/`.
- One task, one branch, one worktree: [worktrees-and-branches.md](worktrees-and-branches.md).
- Agents never commit, push, or deploy. A human reviews, then the reviewer agent approves.

## References

- [setup-macos.md](setup-macos.md)
- [commands.md](commands.md)
- [start-stop.md](../operation/start-stop.md)
- [health-check.md](../operation/health-check.md)
- [playerbot-rig.md](../operation/playerbot-rig.md)
- [logs-and-monitoring.md](../operation/logs-and-monitoring.md)
