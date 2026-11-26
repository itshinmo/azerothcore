#!/usr/bin/env python3
"""Generate the baked map-POI tables for the ServerMapPOI addon.

Reads ``WorldMapArea.dbc`` and ``DungeonMap.dbc`` from the highest-priority archive in the client
``Data`` tree, plus the harvested spawn snapshot in ``poidata/snapshot.json``, converts world
coordinates with the 3.3.5 zone-map convention, and writes ``src/ServerMapPOI/Data.lua``.

The 3.3.5 zone maps are rotated. ``WorldMapArea`` stores Y boundaries in LocLeft/LocRight and X
boundaries in LocTop/LocBottom, so:

    mapX = (yMax - worldY) / (yMax - yMin)
    mapY = (xMax - worldX) / (xMax - xMin)

Usage::

    python3 data/client-patches/map-poi/harvest_poi_data.py --user ... --password ...
    python3 data/client-patches/map-poi/generate_poi_data.py
    python3 data/client-patches/map-poi/generate_poi_data.py --check

Coordinates are a snapshot. Re-run the harvest, then this script, then rebuild ``patch-Z.MPQ``.
"""

from __future__ import annotations

import argparse
import json
import os
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "client-patch"))

import mpq  # noqa: E402

DEFAULT_CLIENT = os.environ.get("WOW_CLIENT", os.path.expanduser("~/Games/wotlk-clean"))
LOCALE = "enUS"
SNAPSHOT_FILE = Path(__file__).resolve().parent / "poidata" / "snapshot.json"
OUT = Path(__file__).resolve().parent / "src" / "ServerMapPOI" / "Data.lua"

# Zones we name explicitly. Bounds are read for EVERY zone that WorldMapArea knows about, because
# flight masters and innkeepers exist across the whole world; this table only supplies friendly
# names and marks the zones we care about by name.
NAMED_ZONES = {
    1497: "Undercity",
    1519: "Stormwind City",
    1537: "Ironforge",
    1637: "Orgrimmar",
    1638: "Thunder Bluff",
    1657: "Darnassus",
    3483: "Hellfire Peninsula",
    3487: "Silvermoon City",
    3520: "Shadowmoon Valley",
    3557: "The Exodar",
    3703: "Shattrath City",
    3518: "Nagrand",
    4395: "Dalaran",
}

# Dalaran's city map uses DungeonMap floor 27 on map 571. WorldMapArea has zero bounds for zone
# 4395, so the DungeonMap bounds are used.
DALARAN_ZONE_ID = 4395
DALARAN_MAP_ID = 571
DALARAN_DUNGEON_MAP_ID = 27

# Hand-placed markers that no world table can generate: the capital Warpweaver spawns (one per
# city, creature entry 910012), the outdoor bosses, and the 15 call boards placed by
# data/sql/custom/db_world/call_boards.sql. Coordinates are real spawn positions: the first two
# groups come from the harvest, the boards from AWE area overview plus acore-data terrain.
STATIC_POIS = [
    (1519, -8829.3, 598.9, "warpweaver", "Warpweaver", "Transmogrifier", "neutral"),
    (1537, -4959.6, -1021.3, "warpweaver", "Warpweaver", "Transmogrifier", "neutral"),
    (1657, 9926.8, 2319.0, "warpweaver", "Warpweaver", "Transmogrifier", "neutral"),
    (3557, -3931.7, -11625.6, "warpweaver", "Warpweaver", "Transmogrifier", "neutral"),
    (1637, 1894.1, -4324.3, "warpweaver", "Warpweaver", "Transmogrifier", "neutral"),
    (1497, 1581.6, 190.5, "warpweaver", "Warpweaver", "Transmogrifier", "neutral"),
    (1638, -1244.6, -60.6, "warpweaver", "Warpweaver", "Transmogrifier", "neutral"),
    (3487, 9870.2, -7442.9, "warpweaver", "Warpweaver", "Transmogrifier", "neutral"),
    (3703, -2006.6, 5371.1, "warpweaver", "Warpweaver", "Transmogrifier", "neutral"),
    (4395, 5842.8, 721.8, "warpweaver", "Warpweaver", "Transmogrifier", "neutral"),
    (3483, 943.5, 2269.8, "boss", "Doom Lord Kazzak", "Outdoor raid boss", "neutral"),
    (3520, -3563.3, 233.9, "boss", "Doomwalker", "Outdoor raid boss", "neutral"),
    (1519, -8863.883407, 669.521069, "callboard", "Call Board", "Alliance call board", "alliance"),
    (1537, -4839.809440, -862.526259, "callboard", "Call Board", "Alliance call board", "alliance"),
    (1657, 10125.787802, 2230.085151, "callboard", "Call Board", "Alliance call board", "alliance"),
    (3557, -3751.869951, -11696.123140, "callboard", "Call Board", "Alliance call board", "alliance"),
    (1637, 1629.452468, -4435.918796, "callboard", "Call Board", "Horde call board", "horde"),
    (1497, 1629.701764, 223.504511, "callboard", "Call Board", "Horde call board", "horde"),
    (1638, -1294.820848, 40.128255, "callboard", "Call Board", "Horde call board", "horde"),
    (3487, 9569.866650, -7226.669362, "callboard", "Call Board", "Horde call board", "horde"),
    (3703, -2180.831174, 5404.332052, "callboard", "Call Board", "Neutral call board", "neutral"),
    (4395, 5850.769034, 637.283083, "callboard", "Call Board", "Neutral call board", "neutral"),
    (33, -14460.265250, 490.256881, "callboard", "Call Board", "Neutral call board", "neutral"),
    (440, -7162.411254, -3837.072506, "callboard", "Call Board", "Neutral call board", "neutral"),
    (618, 6699.864284, -4670.207065, "callboard", "Call Board", "Neutral call board", "neutral"),
    (3523, 3064.123887, 3696.471751, "callboard", "Call Board", "Neutral call board", "neutral"),
    (17, -1044.339607, -3664.874299, "callboard", "Call Board", "Neutral call board", "neutral"),
]

# Zones that get the translucent red PvP overlay. The owner's list is the six contested open-world
# zones; the two stock battlegrounds stay on the list as well so their maps keep the highlight they
# had before the layer was expanded.
RED_ZONES = {
    1377: "Silithus",
    139: "Eastern Plaguelands",
    3483: "Hellfire Peninsula",
    3518: "Nagrand",
    4197: "Wintergrasp",
    3521: "Zangarmarsh",
    4384: "Strand of the Ancients",
    4710: "Isle of Conquest",
}

# Maps that are instances, read from Map.dbc (InstanceType != 0). Capitals on Outland and Northrend
# use world maps 530 and 571, which are type 0, so they stay drawable.

# Faction from creature_template.faction: 1 = human/Alliance, 2 = orc/Horde in the stock data.
# Rather than trust that mapping, flight master tint is decided by zone, which is unambiguous.
ALLIANCE_ZONES = {1519, 1537, 1657, 3557}
HORDE_ZONES = {1637, 1497, 1638, 3487}


def dbc(data: bytes) -> tuple[list[list[int]], bytes]:
    magic, count, fields, record_size, _string_size = struct.unpack_from("<4s4I", data, 0)
    if magic != b"WDBC":
        raise ValueError("not a WDBC file")
    rows = [
        list(struct.unpack_from(f"<{fields}I", data, 20 + index * record_size))
        for index in range(count)
    ]
    strings = data[20 + count * record_size:]
    return rows, strings


def dbc_string(strings: bytes, offset: int) -> str:
    if not offset:
        return ""
    end = strings.find(b"\0", offset)
    return strings[offset:end].decode("utf-8", "replace")


def as_float(value: int) -> float:
    return struct.unpack("<f", struct.pack("<I", value))[0]


def load_table(data_dir: Path, name: str) -> tuple[list[list[int]], bytes, dict, int]:
    path = f"DBFilesClient\\{name}.dbc"
    result = mpq.find_highest(data_dir, path, locale=LOCALE, order="english")
    if not result.winner:
        raise SystemExit(f"cannot find {path} in {data_dir}")
    with mpq.Archive(result.winner) as archive:
        data = archive.read_file(path)
        digest = mpq.sha256_bytes(data)
    rows, strings = dbc(data)
    fields = struct.unpack_from("<4s4I", data, 0)[2]
    try:
        relative = result.winner.relative_to(data_dir.parent)
    except ValueError:
        relative = Path(result.winner.name)
    source = {"archive": relative.as_posix(), "sha256": digest}
    return rows, strings, source, fields


def zone_bounds(rows: list[list[int]], strings: bytes, fields: int,
                areas: dict[int, dict]) -> dict[int, dict]:
    """Every WorldMapArea row that has usable bounds, keyed by zone id.

    A zone can appear several times (floors, children); the first usable row wins. Rows with
    inverted or zero bounds are skipped rather than raising, because some are legitimate
    sub-areas with no map of their own.
    """
    if fields not in (10, 11):
        raise SystemExit(
            f"WorldMapArea.dbc has {fields} fields; expected 10 (stock) or 11 (this bundle)"
        )
    bounds = {}
    for row in rows:
        area = row[2]
        if area == DALARAN_ZONE_ID:
            continue  # zero bounds in WorldMapArea; DungeonMap supplies them
        if area in bounds:
            continue
        y_max, y_min = as_float(row[4]), as_float(row[5])
        x_max, x_min = as_float(row[6]), as_float(row[7])
        if y_max <= y_min or x_max <= x_min:
            continue
        name = NAMED_ZONES.get(area)
        if not name:
            area_row = areas.get(area)
            name = area_row["name"] if area_row else ""
        if not name:
            name = dbc_string(strings, row[3]) or f"zone {area}"
        bounds[area] = {
            "name": name,
            "map": row[1],
            "yMax": y_max, "yMin": y_min, "xMax": x_max, "xMin": x_min,
        }
    return bounds


def dalaran_bounds(rows: list[list[int]]) -> dict | None:
    for row in rows:
        if row[0] == DALARAN_DUNGEON_MAP_ID and row[1] == DALARAN_MAP_ID:
            return {
                "name": "Dalaran",
                "map": DALARAN_MAP_ID,
                "yMax": as_float(row[4]),
                "yMin": as_float(row[3]),
                "xMax": as_float(row[6]),
                "xMin": as_float(row[5]),
            }
    return None


def area_table(data_dir: Path) -> dict[int, dict]:
    """Area id -> {name, zone, map, flags}. Used to resolve a spawn's zone."""
    path = "DBFilesClient\\AreaTable.dbc"
    result = mpq.find_highest(data_dir, path, locale=LOCALE, order="english")
    if not result.winner:
        raise SystemExit(f"cannot find {path} in {data_dir}")
    with mpq.Archive(result.winner) as archive:
        data = archive.read_file(path)
    rows, strings = dbc(data)
    out = {}
    for row in rows:
        out[row[0]] = {
            "map": row[1],
            "zone": row[2],
            "flags": row[4],
            "name": dbc_string(strings, row[11]),
        }
    return out


def instance_map_ids(data_dir: Path) -> set[int]:
    """Map ids whose InstanceType is non-zero. Used to drop markers on maps the world map cannot open."""
    path = "DBFilesClient\\\\Map.dbc"
    result = mpq.find_highest(data_dir, path, locale=LOCALE, order="english")
    if not result.winner:
        return set()
    with mpq.Archive(result.winner) as archive:
        data = archive.read_file(path)
    rows, _strings = dbc(data)
    return {row[0] for row in rows if len(row) > 2 and row[2] != 0}


def dungeon_levels(data_dir: Path) -> dict[int, dict]:
    """Instance map id -> {name, min, max} from LFGDungeons.dbc.

    Field layout, measured on this bundle: 0 id, 1 name, 2 type, 18 min level, 19 max level,
    23 map id. A meeting stone's ``data2`` is an areaID (see GameObjectData.h), and that area's
    map is the instance map, so the chain is: stone area -> AreaTable.map -> this table.
    """
    path = "DBFilesClient\\LFGDungeons.dbc"
    result = mpq.find_highest(data_dir, path, locale=LOCALE, order="english")
    if not result.winner:
        return {}
    with mpq.Archive(result.winner) as archive:
        data = archive.read_file(path)
    rows, strings = dbc(data)
    out: dict[str, dict] = {}
    for row in rows:
        if len(row) < 24:
            continue
        map_id = row[23]
        minimum, maximum = row[18], row[19]
        if not map_id or not minimum or not maximum:
            continue
        # LFGDungeons.type: 0 = dungeon, 1 = raid. Holiday/event and placeholder rows (Coren
        # Direbrew, Headless Horseman) are not dungeons a meeting stone summons to.
        if row[2] not in (0, 1):
            continue
        name = dbc_string(strings, row[1])
        if not name:
            continue
        # Key by name: several dungeons share a map (Hellfire Citadel has four wings on map 540),
        # and holiday rows (Coren Direbrew, Headless Horseman, Crown Chemical Co.) share a map with
        # the real dungeon. Keying by map would pick an event name and a wrong range.
        key = name.strip().lower()
        existing = out.get(key)
        if existing:
            existing["min"] = min(existing["min"], minimum)
            existing["max"] = max(existing["max"], maximum)
        else:
            out[key] = {"name": name, "min": minimum, "max": maximum}
    return out


def resolve_zone(area_id: int, zone_id: int, areas: dict[int, dict],
                  bounds: dict[int, dict]) -> int | None:
    """Pick the drawable zone for a spawn: its own zone id first, then the area's parent zone."""
    if zone_id and zone_id in bounds:
        return zone_id
    area = areas.get(area_id)
    if area:
        if area["zone"] and area["zone"] in bounds:
            return area["zone"]
        if area_id and area_id in bounds:
            return area_id
    return None


def find_zone_by_position(map_id: int, world_x: float, world_y: float,
                          bounds: dict[int, dict]) -> int | None:
    """Resolve a spawn that carries no zone id by finding the smallest zone rectangle containing it.

    Several zone rectangles can overlap on one map, so the smallest wins: that is the more specific
    zone, which is what the player sees named on the map.
    """
    best = None
    best_area = None
    for area_id, b in bounds.items():
        if b.get("map") != map_id:
            continue
        if not (b["xMin"] <= world_x <= b["xMax"] and b["yMin"] <= world_y <= b["yMax"]):
            continue
        size = (b["xMax"] - b["xMin"]) * (b["yMax"] - b["yMin"])
        if best is None or size < best:
            best = size
            best_area = area_id
    return best_area


def format_number(value: float) -> str:
    return f"{value:.6f}".rstrip("0").rstrip(".")


def lua_quote(text: str) -> str:
    return json.dumps(text, ensure_ascii=False)


def transport_dock(name: str) -> tuple[str, str]:
    """Split a transports.name into (route, faction). The stock format is
    'A and B (Zeppelin, Horde ("The Iron Eagle"))'."""
    faction = "neutral"
    lowered = name.lower()
    if ", horde" in lowered:
        faction = "horde"
    elif ", alliance" in lowered:
        faction = "alliance"
    # The stock names nest a quoted ship name inside the parentheses:
    #   'A, B and C, D (Zeppelin, Horde ("The Iron Eagle"))'
    # so the route is everything before the first opening parenthesis.
    route = name
    open_paren = route.find("(")
    if open_paren > 0:
        route = route[:open_paren].strip()
    return route, faction


def generate(client: Path) -> tuple[str, dict]:
    data_dir = client / "Data"
    wma_rows, wma_strings, wma_source, wma_fields = load_table(data_dir, "WorldMapArea")
    dungeon_rows, _, dungeon_source, _ = load_table(data_dir, "DungeonMap")
    areas = area_table(data_dir)
    dungeons = dungeon_levels(data_dir)
    instance_maps = instance_map_ids(data_dir)
    bounds = zone_bounds(wma_rows, wma_strings, wma_fields, areas)
    missing = [zone for zone in NAMED_ZONES if zone not in bounds and zone != DALARAN_ZONE_ID]
    if missing:
        raise SystemExit(f"WorldMapArea has no bounds for named zones: {missing}")
    dalaran = dalaran_bounds(dungeon_rows)
    if not dalaran:
        raise SystemExit(
            f"DungeonMap.dbc has no floor {DALARAN_DUNGEON_MAP_ID} for map {DALARAN_MAP_ID}"
        )
    bounds[DALARAN_ZONE_ID] = dalaran

    snapshot = json.loads(SNAPSHOT_FILE.read_text(encoding="utf-8"))
    pois: list[dict] = []
    skipped = {"creature_no_zone": 0, "portal_no_zone": 0, "stone_no_zone": 0}

    dropped = {"out_of_bounds": 0}

    def add(zone: int, world_x: float, world_y: float, kind: str, label: str, note: str,
            faction: str = "neutral") -> None:
        bound = bounds[zone]
        map_x = (bound["yMax"] - world_y) / (bound["yMax"] - bound["yMin"])
        map_y = (bound["xMax"] - world_x) / (bound["xMax"] - bound["xMin"])
        if not (0.0 <= map_x <= 1.0 and 0.0 <= map_y <= 1.0):
            # A spawn outside the drawn bounds is dropped rather than drawn wrongly, but it must be
            # counted: a spawn move must never silently remove a marker.
            dropped["out_of_bounds"] += 1
            return
        pois.append({
            "zone": zone, "kind": kind, "label": label, "note": note, "faction": faction,
            "worldX": world_x, "worldY": world_y, "mapX": map_x, "mapY": map_y,
        })

    # Creatures: flight masters, innkeepers, battlemasters.
    #
    # Battlemasters are duplicated heavily: the same emissary stands at 20-25 spots per city, so a
    # raw dump puts ~960 dots on the capitals. Collapse to one marker per (zone, name), placed at
    # the spawn closest to the zone's own centroid, so the marker sits in the cluster the player
    # actually walks to.
    buckets: dict[tuple[int, str, str], list[dict]] = {}
    for c in snapshot["creatures"]:
        if c["map"] in instance_maps:
            continue
        zone = resolve_zone(c["area"], c["zone"], areas, bounds)
        if zone is None:
            skipped["creature_no_zone"] += 1
            continue
        if c["flightmaster"]:
            kind, kind_note = "flightmaster", "Flight master"
        elif c["innkeeper"]:
            kind, kind_note = "innkeeper", "Innkeeper"
        elif c["battlemaster"]:
            kind, kind_note = "battlemaster", "Battlemaster"
        else:
            continue
        buckets.setdefault((zone, c["name"], kind), []).append((c, kind_note))

    for (zone, name, kind), items in sorted(buckets.items()):
        bound = bounds[zone]
        centre_x = (bound["xMax"] + bound["xMin"]) / 2.0
        centre_y = (bound["yMax"] + bound["yMin"]) / 2.0
        best, kind_note = min(items, key=lambda item: (item[0]["x"] - centre_x) ** 2
                                                      + (item[0]["y"] - centre_y) ** 2)
        faction = "alliance" if zone in ALLIANCE_ZONES else (
            "horde" if zone in HORDE_ZONES else "neutral")
        add(zone, best["x"], best["y"], kind, name, kind_note, faction)

    # Meeting stones: the instance they summon to gets the note.
    for s in snapshot["meeting_stones"]:
        if s["map"] in instance_maps:
            continue
        zone = resolve_zone(s["area"], s["zone"], areas, bounds)
        if zone is None:
            zone = find_zone_by_position(s["map"], s["x"], s["y"], bounds)
        if zone is None:
            skipped["stone_no_zone"] += 1
            continue
        # data2 is the dungeon's own areaID, and the area's name is the dungeon's name, so the
        # range comes from the LFD row of the same name. Keying by map would confuse the four
        # Hellfire Citadel wings and the holiday bosses that share a map.
        dungeon_area = areas.get(s.get("data2", 0))
        dungeon = dungeons.get(dungeon_area["name"].strip().lower()) if dungeon_area else None
        if dungeon:
            label = dungeon_area["name"]
            note = "%s (%d-%d)" % (label, dungeon["min"], dungeon["max"])
        else:
            label = "Meeting Stone"
            note = "Dungeon meeting stone"
        add(zone, s["x"], s["y"], "meetingstone", label, note)

    # Portals: destination is in the template name.
    for p in snapshot["portals"]:
        if p["map"] in instance_maps:
            continue
        zone = resolve_zone(p["area"], p["zone"], areas, bounds)
        if zone is None:
            zone = find_zone_by_position(p["map"], p["x"], p["y"], bounds)
        if zone is None:
            skipped["portal_no_zone"] += 1
            continue
        add(zone, p["x"], p["y"], "portal", p["name"], "Portal")

    # Ships and zeppelins are deliberately not drawn yet. Their dock positions are not derivable
    # from the tables: `transports` has no coordinates, and `TransportAnimation.dbc` is keyed by a
    # different id space than `transports.entry`. Shipping a marker at a guessed dock would be
    # worse than shipping none. See the README for the follow-up.

    # Hand-placed markers: Warpweavers and the outdoor bosses, which no world table can generate.
    for zone, world_x, world_y, kind, label, note, faction in STATIC_POIS:
        if zone in bounds:
            add(zone, world_x, world_y, kind, label, note, faction)

    # Deduplicate exact duplicates (several spawns can share a position, e.g. stacked innkeepers).
    seen = set()
    unique = []
    for poi in pois:
        key = (poi["zone"], poi["kind"], poi["label"], round(poi["worldX"], 1),
               round(poi["worldY"], 1))
        if key in seen:
            continue
        seen.add(key)
        unique.append(poi)

    lines = [
        "-- Generated by generate_poi_data.py; do not edit by hand.",
        f"-- Client DBCs: WorldMapArea ({Path(wma_source['archive']).name}),",
        f"-- DungeonMap ({Path(dungeon_source['archive']).name}).",
        f"-- Spawn snapshot: {snapshot['generated']} (poidata/snapshot.json).",
        "local ADDON, ns = ...",
        "",
        f'ns.Generated = "{snapshot["generated"]}"',
        "",
        "ns.ZoneBounds = {",
    ]
    for zone in sorted(bounds):
        b = bounds[zone]
        lines.append("    [%d] = {" % zone)
        lines.append("        name = %s," % lua_quote(b["name"]))
        lines.append("        yMax = %s, yMin = %s," % (format_number(b["yMax"]),
                                                     format_number(b["yMin"])))
        lines.append("        xMax = %s, xMin = %s," % (format_number(b["xMax"]),
                                                     format_number(b["xMin"])))
        lines.append("    },")
    lines += ["}", "", "ns.RedZones = {"]
    for zone in sorted(RED_ZONES):
        lines.append("    [%d] = true, -- %s" % (zone, RED_ZONES[zone]))
    lines += ["}", "", "ns.POIs = {"]
    for poi in unique:
        lines.append("    {")
        lines.append("        zone = %d, kind = %s, faction = %s,"
                     % (poi["zone"], lua_quote(poi["kind"]), lua_quote(poi["faction"])))
        lines.append("        label = %s, note = %s,"
                     % (lua_quote(poi["label"]), lua_quote(poi["note"])))
        lines.append("        worldX = %s, worldY = %s,"
                     % (format_number(poi["worldX"]), format_number(poi["worldY"])))
        lines.append("        mapX = %s, mapY = %s," % (format_number(poi["mapX"]),
                                                      format_number(poi["mapY"])))
        lines.append("    },")
    lines += ["}", ""]

    by_kind: dict[str, int] = {}
    for poi in unique:
        by_kind[poi["kind"]] = by_kind.get(poi["kind"], 0) + 1
    metadata = {
        "generated": snapshot["generated"],
        "snapshot_sha256": __import__("hashlib").sha256(
            SNAPSHOT_FILE.read_bytes()).hexdigest(),
        "dropped_out_of_bounds": dropped['out_of_bounds'],
        "world_map_area": wma_source,
        "dungeon_map": dungeon_source,
        "counts": by_kind,
        "skipped": skipped,
        "pois": len(unique),
        "red_zones": RED_ZONES,
    }
    return "\n".join(lines), metadata


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--client", default=DEFAULT_CLIENT, help="client root (contains Data/)")
    parser.add_argument("--out", default=str(OUT))
    parser.add_argument("--check", action="store_true", help="fail if the output is stale")
    args = parser.parse_args()

    if not SNAPSHOT_FILE.exists():
        raise SystemExit(f"{SNAPSHOT_FILE} is missing; run harvest_poi_data.py first")

    text, metadata = generate(Path(args.client).expanduser())
    out = Path(args.out)
    if args.check:
        if not out.exists() or out.read_text(encoding="utf-8") != text:
            print(f"{out} is stale; re-run without --check", file=sys.stderr)
            return 1
        print(f"{out}: up to date")
        return 0
    out.write_text(text, encoding="utf-8")
    print(f"wrote {out}")
    print(f"  {metadata['pois']} markers")
    for kind, count in sorted(metadata["counts"].items()):
        print(f"    {kind:14} {count}")
    if any(metadata["skipped"].values()):
        print(f"  skipped (no drawn zone): {metadata['skipped']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
