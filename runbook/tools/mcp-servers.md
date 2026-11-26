# MCP servers

## When to use

You need the agent to read the live world database, a DBC or terrain without writing ad-hoc Python,
or to inspect a place in the 3D editor before placing something. The agent uses the MCP tools
directly; this runbook is for installing, checking and constraining them.

The project has two project-local servers:

| Server | Transport | What it is for | Writes |
|--------|-----------|----------------|--------|
| `acore-data` | local stdio (Python) | DBC, SQL, terrain, spawns, C++ enums, playerbots | Read-only (`ACORE_SQL_TOOL_MODE=readonly`) |
| `awe` | remote Streamable HTTP, `127.0.0.1:47600/mcp` | Azeroth World Editor's world lookups, camera, screenshots and project drafting | The open AWE project only; never the world database |

They are project-local on purpose. A global server would load its tools into every session and every
project. The only file that holds the connection is `opencode.json` in the repository root, and it is
kept out of git because it holds the AWE token.

## Prerequisites

- OpenCode V2 with the project config at `opencode.json` (or `.opencode/opencode.json`).
- `acore-data` cloned at `~/acore-data` with its own `.venv`.
- Azeroth World Editor 0.10.0 or newer, open, connected to `acore_world`, with **Settings > MCP / AI >
  Allow AI to edit this project** enabled.
- The local MySQL credentials in `env/dist/etc/worldserver.conf`. `acore-data` reads them itself; do
  not copy the password into `opencode.json`.

## Install acore-data

```sh
git clone https://github.com/avirar/acore-data ~/acore-data
cd ~/acore-data
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Project config. The paths match this checkout; change them on another machine.

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "acore-data": {
        "type": "local",
        "command": ["/Users/gasman/acore-data/.venv/bin/python3", "server.py"],
        "cwd": "/Users/gasman/acore-data",
        "environment": {
          "ACORE_DBC_PATH": "/Users/gasman/wow/Data/dbc",
          "ACORE_FORMAT_FILE": "/Users/gasman/wow/azerothcore/src/server/shared/DataStores/DBCfmt.h",
          "ACORE_DATA_PATH": "/Users/gasman/wow/Data",
          "ACORE_SRC_ROOT": "/Users/gasman/wow/azerothcore",
          "ACORE_WORLDSERVER_CONF": "/Users/gasman/wow/azerothcore/env/dist/etc/worldserver.conf",
          "ACORE_SQL_TOOL_MODE": "readonly"
        }
      }
    }
  }
}
```

`ACORE_WORLDSERVER_CONF` makes the server auto-detect the four databases, including
`acore_playerbots`. `ACORE_DATA_PATH` is the folder that holds `maps/`, `vmaps/` and `mmaps/`, not
the `dbc/` folder. Without `pymysql` the server falls back to the `mysql` CLI; the venv is the
supported path.

Start it through OpenCode, not by hand:

```sh
opencode mcp list
```

It should print `✓ acore-data connected`. OpenCode spawns the stdio process itself.

## Install AWE

1. Open the app and connect it to `acore_world`.
2. Open **Settings > MCP / AI**.
3. Tick **Allow AI to edit this project**.
4. Copy the address (default `http://127.0.0.1:47600/mcp`) and press **Show** or **Copy token**.
5. Add the server to `opencode.json`:

```jsonc
"awe": {
  "type": "remote",
  "url": "http://127.0.0.1:47600/mcp",
  "oauth": false,
  "headers": {
    "Authorization": "Bearer {env:AWE_MCP_TOKEN}"
  }
}
```

`oauth` is `false` because the app uses a bearer token, not OAuth. The app listens on loopback only.
The token changes when **Make a new token** is pressed; a client using the old token is refused.

The token is a secret:

- Do not commit it. `opencode.json` is in `.git/info/exclude` for this checkout.
- Export `AWE_MCP_TOKEN` before OpenCode starts, or use a literal token in the local, excluded file.
- Never paste the token into chat, a ticket, or a screenshot.

If the env route is awkward for a desktop launch, the literal-token form is acceptable **only** while
the file stays untracked. Rotate the token after sharing the machine.

## Verify

```sh
opencode mcp list
```

Expected:

```text
✓ acore-data  connected
✓ awe         connected
```

AWE returns `401` when the token is wrong or the app is not running. It returns a connection error
when the app is closed. Both are configuration states, not server faults.

Useful first calls:

- `acore-data.dbversion()` — core revision, DB version, pending updates.
- `acore-data.query({name: "WorldMapArea", filter: {area_id: 1519}})` — DBC row. Use `filter` for
  DBC fields; `lookup(query: "WorldMapArea")` lists the field names.
- `acore-data.enums({enum: "Mechanics", value: 17})` — decode a magic number from the C++ source.
- `awe.camera_status()` — where the 3D camera is.
- `awe.area_overview({map: 0, x: -8867.8, y: 673.7, radius: 6})` — NPCs and objects around a point,
  with z, orientation, facing and rotation.

## Placement workflow

The call boards are the worked example. The agent did not guess coordinates:

1. `acore-data` / the POI data gave each innkeeper's real anchor.
2. `awe.area_overview` returned the innkeeper's z, facing, and the nearby floor objects.
3. `acore-data.terrain({subcommand: "position", ...})` returned the vmap floor at the chosen spot.
4. The SQL used a **registry** gameobject ID, `930101`, and reserved spawn GUIDs
   `5714521-5714535` — not AWE's allocator.

That last point is the rule. AWE's own allocator starts at `60000`, below every project block. Its
`allocate_ids` tool is useful for a scratch project, but a row that enters the repository needs an ID
from [id-registry.md](../database/id-registry.md). New content belongs in tracked SQL, not in an AWE
export that the next person cannot reproduce.

AWE writes the open project only. It cannot write `acore_world`, and it cannot apply a patch to a dev
database. Export, review and apply remain human steps.

## Security and boundaries

- **Read-only SQL.** `ACORE_SQL_TOOL_MODE=readonly` allows `SELECT` only. It is a code guard, not a
  grant: the `acore` user can write. For a stronger boundary, create a `SELECT`-only MySQL user and
  point `acore-data` at it. Do not change the server's `acore` account.
- **Player data.** The tool can see `acore_auth` and `acore_characters`. Never paste account rows,
  IPs, or character data into chat, commits, logs, or issues. Use IDs and aggregate counts.
- **AWE token.** Local secret. Excluded file only. Rotate it if it leaks.
- **No SOAP admin MCP.** `Lingelo/azerothcore-wotlk-mcp` exposes 28 SOAP GM tools, including account
  create/delete, bans, mail, level changes and `raw_command`. It bypasses the GM API, RBAC and audit
  rows and would let an agent write a live realm. It is not installed. GM actions go through the
  audited API or a human at the console.
- **Context budget.** Each server adds tool schemas to every session in this project. Keep the set to
  these two; add a third only when its job cannot be done with the shell.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `awe failed: ... HTTP 401` | Token placeholder, wrong token, or app restarted with a new token | Copy the token again; update the header; save |
| `awe` connection refused | App closed, MCP tab off, or wrong port | Open the app; enable MCP / AI; use the address shown there |
| `acore-data` starts then exits | Venv missing `pymysql`, or wrong `server.py` path | `.venv/bin/pip install -r requirements.txt`; use the absolute venv Python |
| Database connection refused | `ACORE_WORLDSERVER_CONF` wrong or MySQL down | `make status`; check the path and the DB host |
| `0 matching records` for a DBC | Used `id` on a DBC whose primary key is not exposed | Use `filter` with the names from `lookup` |
| `terrain` says maps missing | `ACORE_DATA_PATH` points at `dbc/` | Point it at the folder that holds `maps/`, `vmaps/`, `mmaps/` |
| AWE writes are invisible in game | AWE wrote its project, not the database | Export the SQL, review it, apply it; or use tracked SQL |
| Token in `git status` | `opencode.json` is tracked or the exclusion was lost | `git check-ignore -v opencode.json`; restore `.git/info/exclude` |

## References

- [azeroth-world-editor.md](azeroth-world-editor.md) — app install, connection fields, export rules.
- [id-registry.md](../database/id-registry.md) — reserved custom ID blocks.
- [apply-sql-update.md](../operation/apply-sql-update.md) — how tracked SQL reaches the world DB.
- [backup-restore.md](../operation/backup-restore.md) — back up before a write batch.
- [secrets-and-config.md](../../.opencode/skills/secrets-and-config/SKILL.md) — secret handling.
- `acore-data`: https://github.com/avirar/acore-data (GPL-2.0)
- AWE: https://github.com/DMCK96/azeroth-world-editor (GPL-3.0-or-later)
