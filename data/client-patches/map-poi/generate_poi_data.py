#!/usr/bin/env python3
"""Generate the baked map-POI tables for the ServerMapPOI addon.

Reads ``WorldMapArea.dbc`` and ``DungeonMap.dbc`` from the highest-priority
archive in the client ``Data`` tree, converts world coordinates with the 3.3.5
zone-map convention, and writes ``src/ServerMapPOI/Data.lua``.

The 3.3.5 zone maps are rotated. ``WorldMapArea`` stores Y boundaries in
LocLeft/LocRight and X boundaries in LocTop/LocBottom, so:

    mapX = (yMax - worldY) / (yMax - yMin)
    mapY = (xMax - worldX) / (xMax - xMin)

Usage::

    python3 data/client-patches/map-poi/generate_poi_data.py
    python3 data/client-patches/map-poi/generate_poi_data.py --check

Spawn coordinates are a snapshot. The Warpweaver snapshot comes from
``acore_world.creature`` for entry 910012 on 2026-11-23; the PvP vendors are
the stock battleground/arena vendor clusters. Re-run this script after a spawn
move and rebuild ``patch-Z.MPQ``.
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
SNAPSHOT = "2026-11-23"
OUT = Path(__file__).resolve().parent / "src" / "ServerMapPOI" / "Data.lua"

ZONES = {
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
}

# Dalaran's city map uses DungeonMap floor 27 on map 571. WorldMapArea has zero
# bounds for zone 4395, so the DungeonMap bounds are used. The arena vendor
# percentages come from in-game locations; the Warpweaver is derived from the
# spawn so the marker follows the SQL/live position.
DALARAN_ZONE_ID = 4395
DALARAN_MAP_ID = 571
DALARAN_DUNGEON_MAP_ID = 27
DALARAN_MAP_OVERRIDES = {
    "vendor": (0.584, 0.580),
}

# zone, world X, world Y, kind, label, note
POIS = [
    (1519, -8829.3, 598.9, "warpweaver", "Warpweaver", "Transmogrifier (entry 910012)"),
    (1537, -4959.6, -1021.3, "warpweaver", "Warpweaver", "Transmogrifier (entry 910012)"),
    (1657, 9926.8, 2319.0, "warpweaver", "Warpweaver", "Transmogrifier (entry 910012)"),
    (3557, -3931.7, -11625.6, "warpweaver", "Warpweaver", "Transmogrifier (entry 910012)"),
    (1637, 1894.1, -4324.3, "warpweaver", "Warpweaver", "Transmogrifier (entry 910012)"),
    (1497, 1581.6, 190.5, "warpweaver", "Warpweaver", "Transmogrifier (entry 910012)"),
    (1638, -1244.6, -60.6, "warpweaver", "Warpweaver", "Transmogrifier (entry 910012)"),
    (3487, 9870.2, -7442.9, "warpweaver", "Warpweaver", "Transmogrifier (entry 910012)"),
    (3703, -2006.6, 5371.1, "warpweaver", "Warpweaver", "Transmogrifier (entry 910012)"),
    (4395, 5842.8, 721.8, "warpweaver", "Warpweaver", "Transmogrifier (entry 910012); Dalaran city map"),
    (1519, -8775.0, 420.0, "vendor", "PvP honor vendors", "Champions' Hall quartermasters"),
    (1519, -8390.3, 285.5, "vendor", "Battlemasters", "Battleground battlemasters"),
    (1537, -5038.2, -1266.1, "vendor", "Battlemasters", "Battleground battlemasters"),
    (1657, 9976.2, 2314.5, "vendor", "Battlemasters", "Battleground battlemasters"),
    (3557, -3980.0, -11358.9, "vendor", "Battlemasters", "Battleground battlemasters"),
    (1637, 1669.1, -4196.8, "vendor", "PvP honor vendors", "Hall of Legends quartermasters"),
    (1637, 1987.1, -4800.8, "vendor", "Battlemasters", "Battleground battlemasters"),
    (1497, 1331.6, 333.7, "vendor", "Battlemasters", "Battleground battlemasters"),
    (1638, -1384.1, -85.3, "vendor", "Battlemasters", "Battleground battlemasters"),
    (3487, 9850.6, -7572.2, "vendor", "Battlemasters", "Battleground battlemasters"),
    (3703, -1766.1, 5257.0, "vendor", "Battlemasters", "Battleground battlemasters"),
    (4395, 5751.5, 584.7, "vendor", "Arena vendors", "Dalaran Underbelly arena quartermasters"),
    (3483, 943.5, 2269.8, "boss", "Doom Lord Kazzak", "Outdoor raid boss"),
    (3520, -3563.3, 233.9, "boss", "Doomwalker", "Outdoor raid boss"),
]

RED_ZONES = {
    4197: "Wintergrasp",
    4384: "Strand of the Ancients",
    4710: "Isle of Conquest",
}


def dbc(data: bytes) -> tuple[list[list[int]], bytes]:
    magic, count, fields, record_size, string_size = struct.unpack_from("<4s4I", data, 0)
    if magic != b"WDBC":
        raise ValueError("not a WDBC file")
    rows = [
        list(struct.unpack_from(f"<{fields}I", data, 20 + index * record_size))
        for index in range(count)
    ]
    strings = data[20 + count * record_size : 20 + count * record_size + string_size]
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


def zone_bounds(rows: list[list[int]], fields: int) -> dict[int, dict]:
    if fields not in (10, 11):
        raise SystemExit(
            f"WorldMapArea.dbc has {fields} fields; expected 10 (stock) or 11 (this bundle)"
        )
    bounds = {}
    for row in rows:
        area = row[2]
        if area == DALARAN_ZONE_ID:
            continue  # zero bounds in WorldMapArea; DungeonMap supplies them
        if area not in ZONES:
            continue
        if area in bounds:
            continue  # first row is the zone map; later rows are floors/children
        bound = {
            "name": ZONES.get(area, "Dalaran"),
            "yMax": as_float(row[4]),
            "yMin": as_float(row[5]),
            "xMax": as_float(row[6]),
            "xMin": as_float(row[7]),
        }
        if bound["yMax"] <= bound["yMin"] or bound["xMax"] <= bound["xMin"]:
            raise SystemExit(f"WorldMapArea.dbc has inverted bounds for area {area}: {bound}")
        bounds[area] = bound
    return bounds


def dalaran_bounds(rows: list[list[int]]) -> dict | None:
    for row in rows:
        if row[0] == DALARAN_DUNGEON_MAP_ID and row[1] == DALARAN_MAP_ID:
            # DungeonMap stores (Ymin, Ymax, Xmin, Xmax) for the micro map.
            return {
                "name": "Dalaran",
                "yMax": as_float(row[4]),
                "yMin": as_float(row[3]),
                "xMax": as_float(row[6]),
                "xMin": as_float(row[5]),
            }
    return None


def format_number(value: float) -> str:
    return f"{value:.6f}".rstrip("0").rstrip(".")


def lua_quote(text: str) -> str:
    return json.dumps(text, ensure_ascii=False)


def generate(client: Path) -> tuple[str, dict]:
    data_dir = client / "Data"
    wma_rows, _, wma_source, wma_fields = load_table(data_dir, "WorldMapArea")
    dungeon_rows, _, dungeon_source, _ = load_table(data_dir, "DungeonMap")
    bounds = zone_bounds(wma_rows, wma_fields)
    missing = [zone for zone in ZONES if zone not in bounds]
    if missing:
        raise SystemExit(f"WorldMapArea has no bounds for zones: {missing}")
    dalaran = dalaran_bounds(dungeon_rows)
    if not dalaran:
        raise SystemExit(
            f"DungeonMap.dbc has no floor {DALARAN_DUNGEON_MAP_ID} for map {DALARAN_MAP_ID}"
        )
    bounds[DALARAN_ZONE_ID] = dalaran

    lines = [
        "-- Generated by generate_poi_data.py; do not edit by hand.",
        f"-- Client DBCs: WorldMapArea ({Path(wma_source['archive']).name}),",
        f"-- DungeonMap ({Path(dungeon_source['archive']).name}).",
        f"-- Spawn snapshot: acore_world {SNAPSHOT}.",
        "local ADDON, ns = ...",
        "",
        f'ns.Generated = "{SNAPSHOT}"',
        "",
        "ns.ZoneBounds = {",
    ]
    for zone in sorted(bounds):
        bound = bounds[zone]
        lines.append("    [%d] = {" % zone)
        lines.append("        name = %s," % lua_quote(bound["name"]))
        lines.append(
            "        yMax = %s, yMin = %s,"
            % (format_number(bound["yMax"]), format_number(bound["yMin"]))
        )
        lines.append(
            "        xMax = %s, xMin = %s,"
            % (format_number(bound["xMax"]), format_number(bound["xMin"]))
        )
        lines.append("    },")
    lines += ["}", "", "ns.RedZones = {"]
    for zone in sorted(RED_ZONES):
        lines.append("    [%d] = true, -- %s" % (zone, RED_ZONES[zone]))
    lines += ["}", "", "ns.POIs = {"]

    computed = []
    for zone, world_x, world_y, kind, label, note in POIS:
        map_x = map_y = None
        if zone == DALARAN_ZONE_ID and kind in DALARAN_MAP_OVERRIDES:
            map_x, map_y = DALARAN_MAP_OVERRIDES[kind]
        else:
            bound = bounds[zone]
            map_x = (bound["yMax"] - world_y) / (bound["yMax"] - bound["yMin"])
            map_y = (bound["xMax"] - world_x) / (bound["xMax"] - bound["xMin"])
            if not (0.0 <= map_x <= 1.0 and 0.0 <= map_y <= 1.0):
                raise SystemExit(
                    f"{label} in {bounds[zone]['name']} is outside map bounds: "
                    f"{map_x:.3f}, {map_y:.3f}"
                )
        computed.append((zone, map_x, map_y, kind, label))
        lines.append("    {")
        lines.append("        zone = %d, kind = %s, label = %s," % (zone, lua_quote(kind), lua_quote(label)))
        lines.append("        note = %s," % lua_quote(note))
        lines.append("        worldX = %s, worldY = %s," % (format_number(world_x), format_number(world_y)))
        lines.append("        mapX = %s, mapY = %s," % (format_number(map_x), format_number(map_y)))
        lines.append("    },")
    lines += ["}", ""]

    metadata = {
        "generated": SNAPSHOT,
        "world_map_area": wma_source,
        "dungeon_map": dungeon_source,
        "pois": [
            {"zone": zone, "mapX": round(map_x, 4), "mapY": round(map_y, 4), "label": label}
            for zone, map_x, map_y, kind, label in computed
        ],
        "red_zones": RED_ZONES,
    }
    return "\n".join(lines), metadata


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--client", default=DEFAULT_CLIENT, help="client root (contains Data/)")
    parser.add_argument("--out", default=str(OUT))
    parser.add_argument("--check", action="store_true", help="fail if the output is stale")
    args = parser.parse_args()

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
    for item in metadata["pois"]:
        print(f"  zone {item['zone']:>4}  {item['mapX'] * 100:6.2f},{item['mapY'] * 100:6.2f}  {item['label']}")
    print(json.dumps({k: metadata[k] for k in ("world_map_area", "dungeon_map")}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
