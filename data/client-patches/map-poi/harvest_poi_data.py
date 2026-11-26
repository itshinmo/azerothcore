#!/usr/bin/env python3
"""Harvest the map-POI source data from a live ``acore_world`` into a snapshot file.

The map-POI build must be reproducible without a database, so this script is the only part that
talks to MySQL. It writes ``poidata/snapshot.json``; ``generate_poi_data.py`` then reads that file
and produces ``Data.lua``. Re-run this after any spawn move, then rebuild the patch.

Usage::

    export POI_DB_PASSWORD='...'        # or MYSQL_PWD, or a ~/.my.cnf section
    python3 data/client-patches/map-poi/harvest_poi_data.py --user acore

The password is read from the environment, never from the command line: an argument would show up
in ``ps`` and in shell history. Nothing here writes to the database.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_OUT = HERE / "poidata" / "snapshot.json"

# npcflag bits (src/server/game/Entities/Unit/UnitDefines.h)
FLAG_FLIGHTMASTER = 0x00002000
FLAG_INNKEEPER = 0x00010000
FLAG_BATTLEMASTER = 0x00100000

PORTAL_TEMPLATE_TYPE = 22
MEETINGSTONE_TEMPLATE_TYPE = 23

# A gameobject with type 22 is not necessarily a portal: lance racks, cauldrons, coffins and
# gunship scenery share the type. Keep only names that read as a travel portal.
PORTAL_NAME_ALLOW = ("Portal to ", "Dalaran Portal to ", "Shattrath Portal to ", "Nexus Portal",
                     "Orb of the Nexus")
PORTAL_NAME_DENY = ("Gunship", "Lance Rack", "Surface Portal", "Portal Particles", "Eye Portal")


def query(user: str, password: str, database: str, host: str, sql: str) -> list[list[str]]:
    command = ["mysql", "-h", host, "-u", user, "-N", "-B", "-e", sql]
    env = dict(os.environ)
    env["MYSQL_PWD"] = password
    result = subprocess.run(command, capture_output=True, text=True, env=env)
    if result.returncode != 0:
        # The password warning goes to stderr on success too, so only fail on a real error.
        print(result.stderr.strip(), file=sys.stderr)
        raise SystemExit(f"query failed: {sql.splitlines()[0][:80]}")
    rows = []
    for line in result.stdout.splitlines():
        rows.append(line.split("\t"))
    return rows


def harvest(args) -> dict:
    db = args.database
    rows = query(args.user, args.password, db, args.host, f"""
        SELECT c.guid, c.id, c.map, c.zoneId, c.areaId,
               ROUND(c.position_x, 3), ROUND(c.position_y, 3), ROUND(c.position_z, 3),
               t.name,
               CASE WHEN (t.npcflag & {FLAG_FLIGHTMASTER}) <> 0 THEN 1 ELSE 0 END,
               CASE WHEN (t.npcflag & {FLAG_INNKEEPER}) <> 0 THEN 1 ELSE 0 END,
               CASE WHEN (t.npcflag & {FLAG_BATTLEMASTER}) <> 0 THEN 1 ELSE 0 END,
               t.faction
        FROM {db}.creature c
        JOIN {db}.creature_template t ON c.id = t.entry
        WHERE (t.npcflag & {FLAG_FLIGHTMASTER}) <> 0
           OR (t.npcflag & {FLAG_INNKEEPER}) <> 0
           OR (t.npcflag & {FLAG_BATTLEMASTER}) <> 0
        ORDER BY c.guid
    """)

    creatures = []
    for r in rows:
        creatures.append({
            "guid": int(r[0]),
            "entry": int(r[1]),
            "map": int(r[2]),
            "zone": int(r[3]),
            "area": int(r[4]),
            "x": float(r[5]),
            "y": float(r[6]),
            "z": float(r[7]),
            "name": r[8],
            "flightmaster": r[9] == "1",
            "innkeeper": r[10] == "1",
            "battlemaster": r[11] == "1",
            "faction": int(r[12] or 0),
        })

    objects = query(args.user, args.password, db, args.host, f"""
        SELECT g.guid, g.id, g.map, g.zoneId, g.areaId,
               ROUND(g.position_x, 3), ROUND(g.position_y, 3), ROUND(g.position_z, 3),
               t.name, t.type, t.data2
        FROM {db}.gameobject g
        JOIN {db}.gameobject_template t ON g.id = t.entry
        WHERE t.type IN ({PORTAL_TEMPLATE_TYPE}, {MEETINGSTONE_TEMPLATE_TYPE})
        ORDER BY g.guid
    """)

    portals = []
    meeting_stones = []
    for r in objects:
        name = r[8]
        kind = int(r[9])
        entry = {
            "guid": int(r[0]),
            "entry": int(r[1]),
            "map": int(r[2]),
            "zone": int(r[3]),
            "area": int(r[4]),
            "x": float(r[5]),
            "y": float(r[6]),
            "z": float(r[7]),
            "name": name,
            "data2": int(r[10] or 0),
        }
        if kind == PORTAL_TEMPLATE_TYPE:
            if any(bad in name for bad in PORTAL_NAME_DENY):
                continue
            if not name.startswith(PORTAL_NAME_ALLOW):
                continue
            portals.append(entry)
        else:
            meeting_stones.append(entry)

    transports = query(args.user, args.password, db, args.host, f"""
        SELECT entry, name FROM {db}.transports ORDER BY entry
    """)
    routes = [{"entry": int(r[0]), "name": r[1]} for r in transports]

    return {
        "schema": 1,
        "generated": date.today().isoformat(),
        "source": {"database": db, "tables": ["creature", "creature_template",
                                              "gameobject", "gameobject_template", "transports"]},
        "creatures": creatures,
        "portals": portals,
        "meeting_stones": meeting_stones,
        "transport_routes": routes,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--user", required=True)
    parser.add_argument("--password", default=None,
                        help="defaults to $POI_DB_PASSWORD or $MYSQL_PWD; never pass it as an "
                             "argument, it would appear in ps and shell history")
    parser.add_argument("--database", default="acore_world")
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    args = parser.parse_args()

    if not args.password:
        args.password = os.environ.get("POI_DB_PASSWORD") or os.environ.get("MYSQL_PWD") or ""
    if not args.password:
        raise SystemExit("no password: set POI_DB_PASSWORD or MYSQL_PWD")

    data = harvest(args)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=2, sort_keys=False) + "\n", encoding="utf-8")
    print(f"wrote {out}")
    print(f"  {len(data['creatures'])} creatures "
          f"({sum(c['flightmaster'] for c in data['creatures'])} flight masters, "
          f"{sum(c['innkeeper'] for c in data['creatures'])} innkeepers, "
          f"{sum(c['battlemaster'] for c in data['creatures'])} battlemasters)")
    print(f"  {len(data['portals'])} portals, {len(data['meeting_stones'])} meeting stones, "
          f"{len(data['transport_routes'])} transport routes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
