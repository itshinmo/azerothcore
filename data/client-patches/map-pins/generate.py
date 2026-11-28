#!/usr/bin/env python3
"""Regenerate the WorldMapPins pin data from tracked SQL and the client DBC.

Pin fractions depend on three inputs, and computing them by hand is what produced the ocean-pin
bug, so they are generated and checked:

* the spawn coordinates, from tracked SQL under ``data/sql/custom/db_world/``;
* the zone map bounds, from ``WorldMapArea.dbc`` (or ``DungeonMap.dbc`` when the zone has none);
* the map-530 continent offset, from ``WorldMapTransforms.dbc`` (Silvermoon and the Exodar);
* the transport station nodes, from ``TaxiPathNode.dbc`` (delay > 0 marks a stop);
* the zone display names, from ``AreaTable.dbc``.

shortcut: the 12 portal room coordinates are curated constants with no tracked source. A portal
object that moves ships a stale pin silently; add a ``gameobject`` query to the build when that
happens. Everything else here fails the build when its source moves.

    python3 data/client-patches/map-pins/generate.py
    python3 data/client-patches/map-pins/generate.py --check

``--check`` exits non-zero when a generated file is stale; ``build.py --check`` runs it. The DBC
folder defaults to ``~/wow/Data/dbc`` and is overridden with ``--dbc`` or ``ACORE_DATA``. Each
generated file records the SHA256 of every DBC it read, so a data file can be traced to its source.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import struct
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
DATA_DIR = HERE / "src" / "WorldMapPins" / "data"
DEFAULT_DBC = os.environ.get("ACORE_DATA", os.path.expanduser("~/wow/Data/dbc"))

WARPWEAVER_SQL = ROOT / "data/sql/custom/db_world/collections_npc_spawns.sql"
CALLBOARD_SQL = ROOT / "data/sql/custom/db_world/call_boards.sql"
CALLBOARD_COUNT = 15

# Portal rooms. One pin per room, at the centroid of that room's portal objects, never one pin
# per portal: Shattrath's eight portals span about 145 by 103 yards, so per-object pins would
# overlap and only the top tooltip would ever open. Fields:
# (title, subtitle, map, x, y, zone id, icon name, ("destination", ...)).
PORTAL_ROOMS = [
    (
        "Shattrath City", "Terrace of Light", 530, -1869.6, 5412.5, 3703,
        "Spell_Arcane_PortalShattrath",
        ("Stormwind", "Ironforge", "Darnassus", "The Exodar", "Orgrimmar", "Undercity",
         "Thunder Bluff", "Silvermoon City"),
    ),
    (
        "Shattrath City", "Portal to the Isle of Quel'Danas", 530, -1839.9, 5500.6, 3703,
        "Spell_Arcane_PortalShattrath",
        ("the Isle of Quel'Danas",),
    ),
    (
        "Dalaran", "Silver Enclave", 571, 5707.0, 731.0, 4395,
        "Spell_Arcane_PortalStormWind",
        ("Stormwind", "Ironforge", "Darnassus", "The Exodar", "Shattrath City"),
    ),
    (
        "Dalaran", "Sunreaver's Sanctuary", 571, 5939.0, 582.9, 4395,
        "Spell_Arcane_PortalOrgrimmar",
        ("Orgrimmar", "Undercity", "Thunder Bluff", "Silvermoon City", "Shattrath City"),
    ),
    ("Stormwind City", "Portal to Blasted Lands", 0, -9007.6, 871.9, 1519,
     "Spell_Arcane_PortalStormWind", ("Blasted Lands",)),
    ("Ironforge", "Portal to Blasted Lands", 0, -4606.4, -929.0, 1537,
     "Spell_Arcane_PortalIronForge", ("Blasted Lands",)),
    ("Darnassus", "Portal to Blasted Lands", 1, 9661.8, 2509.6, 1657,
     "Spell_Arcane_PortalDarnassus", ("Blasted Lands",)),
    ("The Exodar", "Portal to Blasted Lands", 530, -4037.8, -11555.5, 3557,
     "Spell_Arcane_PortalExodar", ("Blasted Lands",)),
    ("Undercity", "Portal to Blasted Lands", 0, 1768.8, 55.4, 1497,
     "Spell_Arcane_PortalUnderCity", ("Blasted Lands",)),
    ("Orgrimmar", "Portal to Blasted Lands", 1, 1472.6, -4215.7, 1637,
     "Spell_Arcane_PortalOrgrimmar", ("Blasted Lands",)),
    ("Thunder Bluff", "Portal to Blasted Lands", 1, -944.1, 274.9, 1638,
     "Spell_Arcane_PortalThunderBluff", ("Blasted Lands",)),
    ("Silvermoon City", "Portal to Blasted Lands", 530, 9984.3, -7107.6, 3487,
     "Spell_Arcane_PortalSilvermoon", ("Blasted Lands",)),
]

# Player transport routes from acore_world.transports, keyed by the taxi path id their transport
# gameobject uses. The two Icecrown gunships, the two Northrend turtles and Garvan's Reef are
# deliberately absent: they are not a station a player plans travel around.
# One pin per station node, no merging. Stations are NOT collapsed by distance: the owner wants
# every node visible, and the tooltip names the destination so a stacked pin still reads. Only
# the exact-duplicate node of the Westguard route is deduplicated.
TRANSPORT_PATHS = {
    241: "ship",       # The Maiden's Fancy: Booty Bay - Ratchet
    285: "zeppelin",   # The Iron Eagle: Grom'gol - Orgrimmar
    292: "ship",       # The Lady Mehley: Menethil - Theramore
    293: "ship",       # The Moonspray: Auberdine - Rut'theran Village
    301: "zeppelin",   # The Purple Princess: Grom'gol - Undercity
    302: "zeppelin",   # The Thundercaller: Undercity - Orgrimmar
    503: "ship",       # Elune's Blessing: Auberdine - Valaar's Berth
    712: "zeppelin",   # The Mighty Wind: Orgrimmar - Warsong Hold
    727: "zeppelin",   # Westguard Keep - Shattered Straits (both nodes share one coordinate)
    737: "zeppelin",   # Cloudkisser: Undercity - Vengeance Landing
    777: "ship",       # Feathermoon Ferry: The Forgotten Coast - Feathermoon Stronghold
    964: "ship",       # Northspear: Menethil - Valgarde
    965: "ship",       # Stormwind's Pride: Valiance Keep - Stormwind Harbor
    967: "ship",       # The Bravery: Auberdine - Stormwind Harbor
    1221: "zeppelin",  # The Zephyr: Orgrimmar - Thunder Bluff
}

# Station name and zone per station node, keyed by (map, x, y) rounded to a tenth of a yard.
# TaxiPathNode gives the coordinate; the name and zone a player recognises are curated, because
# a coordinate alone cannot say "Stormwind Harbor" or which city zone it belongs to. A node
# missing here, or an entry no node uses, fails the generator.
STATIONS = {
    (0, -14277.7, 582.9): ("Booty Bay", 33),
    (0, -12464.0, 231.6): ("Grom'gol Base Camp", 33),
    (0, -12406.9, 211.8): ("Grom'gol Base Camp", 33),
    (0, -3905.2, -585.8): ("Menethil Harbor", 11),
    (0, -3712.7, -569.5): ("Menethil Harbor", 11),
    # The Undercity zeppelin towers stand outside the city zone, in Tirisfal Glades.
    (0, 2062.4, 293.0): ("Undercity", 85),
    (0, 2062.6, 235.3): ("Undercity", 85),
    (0, 2056.5, 381.6): ("Undercity", 85),
    (0, -8288.8, 1424.7): ("Stormwind Harbor", 1519),
    (0, -8650.7, 1346.1): ("Stormwind Harbor", 1519),
    (1, -1005.6, -3841.6): ("Ratchet", 17),
    # The Orgrimmar zeppelin towers stand outside the city zone, in Durotar.
    (1, 1360.9, -4631.3): ("Orgrimmar", 14),
    (1, 1318.1, -4658.0): ("Orgrimmar", 14),
    (1, 1185.0, -4144.2): ("Orgrimmar", 14),
    (1, 1125.4, -4134.9): ("Orgrimmar", 14),
    (1, -4016.4, -4740.6): ("Theramore", 15),
    (1, 8534.3, 1018.0): ("Rut'theran Village", 141),
    (1, 6594.6, 769.8): ("Auberdine", 148),
    (1, 6406.0, 822.9): ("Auberdine", 148),
    (1, 6550.4, 938.2): ("Auberdine", 148),
    (1, -4352.4, 2441.2): ("The Forgotten Coast", 357),
    (1, -4200.3, 3281.4): ("Feathermoon Stronghold", 357),
    (1, -1026.9, 375.8): ("Thunder Bluff", 1638),
    (530, -4265.0, -11317.2): ("Valaar's Berth", 3524),
    (571, 1414.0, -3091.5): ("Westguard Keep", 495),
    (571, 1989.4, -6082.8): ("Vengeance Landing", 495),
    (571, 584.0, -5118.9): ("Valgarde", 495),
    (571, 2837.9, 6187.4): ("Warsong Hold", 3537),
    (571, 2218.4, 5119.6): ("Valiance Keep", 3537),
}

# A route whose two station nodes share one coordinate cannot name a direction from that point.
# It becomes one pin titled after the first name, pointing at the second.
SAME_POINT_ROUTES = {727: ("Westguard Keep", "Shattered Straits")}

# The name a player sees, for zones whose WorldMapArea name is compact or misspelled.
PLACES = {
    15: "Dustwallow Marsh",
    16: "Azshara",
    17: "The Barrens",
    47: "The Hinterlands",
    85: "Tirisfal Glades",
    331: "Ashenvale",
    357: "Feralas",
    440: "Gadgetzan",
    495: "Howling Fjord",
    618: "Everlook",
    1497: "Undercity",
    1519: "Stormwind City",
    1537: "Ironforge",
    1637: "Orgrimmar",
    1638: "Thunder Bluff",
    1657: "Darnassus",
    3483: "Hellfire Peninsula",
    3487: "Silvermoon City",
    3520: "Shadowmoon Valley",
    3523: "Area 52",
    3524: "Azuremyst Isle",
    3537: "Borean Tundra",
    3557: "The Exodar",
    3703: "Shattrath City",
    4395: "Dalaran",
}

# A pin draws on its own zone map and on every zone map that CONTAINS it. Geometric containment
# is not usable: the Undercity bounds touch Silverpine Forest and the Western Plaguelands, and
# Thunder Bluff's spawn point falls in Desolace, so a naive rule puts city pins on three maps.
# One curated parent per city, from WorldMapArea, asserted against the city's own spawn point in
# the generator tests. A city with no entry draws only on its own map, which is the safe default.
ZONE_PARENTS = {
    1519: 12,     # Stormwind City     -> Elwynn Forest
    1537: 1,      # Ironforge          -> Dun Morogh
    1657: 141,    # Darnassus          -> Teldrassil
    3557: 3524,   # The Exodar         -> Azuremyst Isle
    1637: 14,     # Orgrimmar          -> Durotar
    1497: 85,     # Undercity          -> Tirisfal Glades
    1638: 215,    # Thunder Bluff      -> Mulgore
    3487: 3430,   # Silvermoon City    -> Eversong Woods
    3703: 3519,   # Shattrath City     -> Terokkar Forest
    # Dalaran is its own micro-map inside Crystalsong Forest, so it has no parent zone map.
}

# A spawn that sits in a named sub-zone a player would use instead of the zone name.
PLACE_OVERRIDES = {
    5714535: "Ratchet",  # Call Board on the Ratchet dock, zone "The Barrens"
}

# Outdoor world bosses. Stock spawns, stable for the client lifetime, so they are listed here
# instead of read from the world database: the generator must also run offline.
BOSSES = [
    (16, "Azuregos", "Classic world boss", 2622.2, -5977.9),
    (47, "Lethon", "Classic world boss", 753.6, -4012.0),
    (10, "Taerar", "Classic world boss", -10428.8, -392.2),
    (357, "Emeriss", "Classic world boss", -2872.7, 1884.2),
    (331, "Ysondre", "Classic world boss", 3301.1, -3732.6),
    (3483, "Doom Lord Kazzak", "The Burning Crusade world boss", 943.5, 2269.8),
    (3520, "Doomwalker", "The Burning Crusade world boss", -3563.3, 233.9),
]

# WorldMapArea zone bounds overlap, so a coordinate alone is ambiguous (Feralas and Mulgore
# both contain Emeriss). The Warpweaver rows carry zone id 0, so the zone of each spawn is
# pinned here by GUID. The GUID block is reserved and ordered by the owning SQL file.
WARPWEAVER_ZONES = {
    5400001: 1519,  # Stormwind, Trade District
    5400002: 1537,  # Ironforge
    5400003: 1657,  # Darnassus
    5400004: 3557,  # The Exodar
    5400005: 1637,  # Orgrimmar
    5400006: 1497,  # Undercity
    5400007: 1638,  # Thunder Bluff
    5400008: 3487,  # Silvermoon City
    5400009: 3703,  # Shattrath City
    5400010: 4395,  # Dalaran
}


class GenerateError(RuntimeError):
    pass


@dataclass(frozen=True)
class Row:
    ints: tuple[int, ...]
    floats: tuple[float, ...]


def read_dbc(path: Path) -> list[Row]:
    """Read a 3.3.5a WDBC file as rows with both int and float readings of each field."""
    try:
        raw = path.read_bytes()
    except OSError as error:
        raise GenerateError(f"cannot read {path}: {error}") from error
    if len(raw) < 20 or raw[:4] != b"WDBC":
        raise GenerateError(f"{path} is not a WDBC file")
    _, records, fields, record_size, _ = struct.unpack("<4sIIII", raw[:20])
    if 20 + records * record_size > len(raw):
        raise GenerateError(f"{path} is truncated")
    rows = []
    for index in range(records):
        block = raw[20 + index * record_size:20 + (index + 1) * record_size]
        rows.append(Row(struct.unpack(f"<{fields}i", block), struct.unpack(f"<{fields}f", block)))
    return rows


def dbc_strings(path: Path) -> bytes:
    raw = path.read_bytes()
    if len(raw) < 20 or raw[:4] != b"WDBC":
        raise GenerateError(f"{path} is not a WDBC file")
    _, records, fields, record_size, string_size = struct.unpack("<4sIIII", raw[:20])
    if fields * 4 != record_size:
        raise GenerateError(f"{path} has record size {record_size} with {fields} fields")
    start = 20 + records * record_size
    if start + string_size > len(raw):
        raise GenerateError(f"{path} string block runs past the end of the file")
    return raw[start:start + string_size]


def string_at(table: bytes, offset: int) -> str:
    if offset < 0 or offset >= len(table):
        raise GenerateError(f"string offset {offset} is outside a {len(table)}-byte string block")
    end = table.find(b"\0", offset)
    if end < 0:
        raise GenerateError(f"string at offset {offset} is not terminated")
    return table[offset:end].decode("utf-8", "replace")


@dataclass(frozen=True)
class Bounds:
    key: int
    map_id: int
    y_min: float
    y_max: float
    x_min: float
    x_max: float
    display_map: int
    floor: int

    @property
    def valid(self) -> bool:
        return self.x_min != self.x_max and self.y_min != self.y_max


class Maps:
    def __init__(self, dbc: Path):
        if not dbc.is_dir():
            raise GenerateError(f"client DBC folder not found: {dbc}")
        self.dbc = dbc
        self.names: dict[int, str] = {}
        self.zone_names: dict[int, str] = {}
        area_path = self.dbc / "AreaTable.dbc"
        area_strings = dbc_strings(area_path)
        for row in read_dbc(area_path):
            self.zone_names[row.ints[0]] = string_at(area_strings, row.ints[11])
        self.zones: list[Bounds] = []
        path = self.dbc / "WorldMapArea.dbc"
        zone_strings = dbc_strings(path)
        for row in read_dbc(path):
            self.zones.append(
                Bounds(
                    key=row.ints[2],
                    map_id=row.ints[1],
                    y_min=row.floats[5],
                    y_max=row.floats[4],
                    x_min=row.floats[7],
                    x_max=row.floats[6],
                    display_map=row.ints[8],
                    floor=row.ints[9],
                )
            )
            self.names[row.ints[2]] = string_at(zone_strings, row.ints[3])
        self.continents = {
            zone.map_id: index
            for index, zone in enumerate([z for z in self.zones if z.key == 0], start=1)
        }
        self.offsets: dict[tuple[int, int], tuple[float, float]] = {}
        for row in read_dbc(self.dbc / "WorldMapTransforms.dbc"):
            # Field 6 is the map the region is drawn onto: 0 Eastern Kingdoms, 1 Kalimdor.
            # Field 0 is the transform region id, not the continent. A row whose target equals
            # its source is a micro-map, not an offset, so it is skipped.
            if row.ints[6] == row.ints[1]:
                continue
            self.offsets[(row.ints[1], row.ints[6])] = (row.floats[7], row.floats[8])
        self.dungeons: list[Bounds] = []
        for row in read_dbc(self.dbc / "DungeonMap.dbc"):
            self.dungeons.append(
                Bounds(
                    key=row.ints[0],
                    map_id=row.ints[1],
                    y_min=row.floats[3],
                    y_max=row.floats[4],
                    x_min=row.floats[5],
                    x_max=row.floats[6],
                    display_map=-1,
                    floor=row.ints[2],
                )
            )

    def map_zone_name(self, zone_id: int) -> str:
        """The name GetMapZones returns, which is AreaTable's name, not WorldMapArea's."""
        name = self.zone_names.get(zone_id) or PLACES.get(zone_id)
        if not name:
            raise GenerateError(f"no client area name for zone {zone_id}")
        return name

    def zone_for(self, map_id: int, x: float, y: float, zone_id: int | None = None) -> Bounds:
        if zone_id:
            for zone in self.zones:
                # A named zone may have zero bounds (Dalaran); bounds_for falls back to DungeonMap.
                if zone.key == zone_id and zone.map_id == map_id:
                    return zone
            raise GenerateError(f"WorldMapArea zone {zone_id} is not on map {map_id}")

        hits = [
            zone
            for zone in self.zones
            if zone.key != 0
            and zone.map_id == map_id
            and zone.valid
            and min(zone.x_min, zone.x_max) <= x <= max(zone.x_min, zone.x_max)
            and min(zone.y_min, zone.y_max) <= y <= max(zone.y_min, zone.y_max)
        ]
        if not hits:
            raise GenerateError(f"no WorldMapArea zone on map {map_id} contains {x}, {y}")
        hits.sort(key=lambda zone: abs((zone.x_max - zone.x_min) * (zone.y_max - zone.y_min)))
        return hits[0]

    def bounds_for(self, zone: Bounds) -> Bounds:
        if zone.valid:
            return zone
        # Dalaran's WorldMapArea row has zero bounds; the DungeonMap row whose id matches the
        # zone's floor carries them.
        for row in self.dungeons:
            if row.map_id == zone.map_id and row.key == zone.floor:
                return row
        raise GenerateError(f"no map bounds for zone {zone.key} ({self.names.get(zone.key)})")

    def fractions(
        self, map_id: int, x: float, y: float, label: str, zone_id: int | None = None
    ) -> dict:
        zone = self.zone_for(map_id, x, y, zone_id)
        bounds = self.bounds_for(zone)
        mx = (bounds.y_max - y) / (bounds.y_max - bounds.y_min)
        my = (bounds.x_max - x) / (bounds.x_max - bounds.x_min)

        display = zone.display_map if zone.display_map in self.continents else zone.map_id
        # The DBC transform offsets are keyed by the display map, which is the continent id the
        # client projects onto (0 Eastern Kingdoms, 1 Kalimdor).
        offset_x, offset_y = self.offsets.get((map_id, display), (0.0, 0.0))
        bx, by = x + offset_x, y + offset_y
        root = next((z for z in self.zones if z.key == 0 and z.map_id == display), None)
        if root is None:
            raise GenerateError(f"{label}: no continent bounds row for map {display}")
        cx = (root.y_max - by) / (root.y_max - root.y_min)
        cy = (root.x_max - bx) / (root.x_max - root.x_min)

        for name, value in (("mx", mx), ("my", my), ("cx", cx), ("cy", cy)):
            if not -0.001 <= value <= 1.001:
                raise GenerateError(f"{label}: {name} = {value:.4f} is off the map")
        return {
            "zone": zone.key,
            "place": PLACES.get(zone.key, self.names.get(zone.key, str(zone.key))),
            "mx": mx,
            "my": my,
            "cont": self.continents[display],
            "cx": cx,
            "cy": cy,
        }


def sql_spawns(path: Path, expected: int) -> list[tuple[int, int, int, float, float]]:
    """(guid, zoneId, map, x, y) for every spawn row in a tracked SQL file's INSERT.

    Rows may use ``@Entry``, and the two spawn files list different columns over several lines,
    so the column list is read from the INSERT header instead of being assumed. A row that cannot
    be parsed is an error, not a skip: a silently dropped pin is a wrong map with a green check.
    """
    text = path.read_text(encoding="utf-8")
    rows: list[tuple[int, int, int, float, float]] = []
    for statement in text.split("INSERT INTO")[1:]:
        head, _, body = statement.partition("VALUES")
        if "position_x" not in head:
            continue
        columns = [
            part.strip().strip("`") for part in head[head.find("(") + 1:head.rfind(")")].split(",")
        ]
        for line in body.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("--"):
                continue
            if not stripped.startswith("("):
                continue
            parts = [part.strip() for part in stripped.strip("(),;").split(",")]
            if len(parts) < len(columns):
                raise GenerateError(f"{path.name}: short row: {stripped[:80]}")
            values = dict(zip(columns, parts))
            try:
                rows.append(
                    (
                        int(values["guid"]),
                        int(values["zoneId"]),
                        int(values["map"]),
                        float(values["position_x"]),
                        float(values["position_y"]),
                    )
                )
            except (KeyError, ValueError) as error:
                raise GenerateError(
                    f"{path.name}: cannot read a spawn row ({error}): {stripped[:80]}"
                ) from error
    if len(rows) != expected:
        raise GenerateError(f"{path.name}: read {len(rows)} spawn rows, expected {expected}")
    return rows


def lua_text(value: str) -> str:
    """Escape a string for a Lua double-quoted literal."""
    return value.replace("\\", "\\\\").replace('"', '\\"')


def render(key: str, header: str, pins: list[dict], dbc_hashes: dict[str, str]) -> str:
    lines = [
        "-- Generated by data/client-patches/map-pins/generate.py. Do not edit by hand.",
        f"-- {header}",
    ]
    for name, digest in sorted(dbc_hashes.items()):
        lines.append(f"-- {name}: sha256 {digest}")
    lines.extend([
        "",
        "local ADDON, ns = ...",
        f"ns.{key} = {{",
    ])
    for pin in pins:
        lines.append(
            f'    {{ kind = "{lua_text(pin["kind"])}", zone = {pin["zone"]}, '
            f'place = "{lua_text(pin["place"])}", label = "{lua_text(pin["label"])}",'
        )
        lines.append(f'      note = "{lua_text(pin["note"])}",')
        if pin.get("title"):
            title = f'      title = "{lua_text(pin["title"])}"'
            if pin.get("subtitle"):
                title += f', subtitle = "{lua_text(pin["subtitle"])}"'
            lines.append(title + ",")
        if pin.get("icon"):
            lines.append(f'      icon = "Interface\\\\Icons\\\\{lua_text(pin["icon"])}",')
        lines.append(
            f'      x = {pin["x"]}, y = {pin["y"]}, '
            f'mx = {pin["mx"]:.4f}, my = {pin["my"]:.4f},'
        )
        lines.append(f'      cont = {pin["cont"]}, cx = {pin["cx"]:.4f}, cy = {pin["cy"]:.4f},')
        extra_zones = pin.get("zones") or []
        if extra_zones:
            joined = ", ".join(str(z) for z in extra_zones)
            lines.append(f"      zones = {{ {joined} }},")
        destinations = pin.get("lines") or []
        if destinations:
            lines.append("      lines = {")
            for destination in destinations:
                lines.append(f'          "{lua_text(destination)}",')
            lines.append("      } },")
        else:
            lines.append("      },")
    lines.extend(["}", ""])
    return "\n".join(lines)


def render_zones(maps: Maps, zone_ids: list[int], dbc_hashes: dict[str, str]) -> str:
    lines = [
        "-- Generated by data/client-patches/map-pins/generate.py. Do not edit by hand.",
        "-- Zone id -> the name GetMapZones returns for it. Pin visibility is matched on this.",
    ]
    for name, digest in sorted(dbc_hashes.items()):
        lines.append(f"-- {name}: sha256 {digest}")
    lines.extend([
        "",
        "local ADDON, ns = ...",
        "ns.Zones = {",
    ])
    for zone_id in sorted(zone_ids):
        name = maps.map_zone_name(zone_id)
        lines.append(f'    [{zone_id}] = "{lua_text(name)}",')
    lines.extend(["}", ""])
    return "\n".join(lines)


def transport_nodes(maps: Maps) -> list[dict]:
    """Station pins derived from TaxiPathNode: every node where the vessel stops.

    TaxiPathNode fields: 0 id, 1 path, 2 index, 3 map, 4..6 x/y/z, 7 flags, 8 delay,
    9 arrival event, 10 departure event. A vessel stops where delay > 0.
    """
    path = maps.dbc / "TaxiPathNode.dbc"
    if not path.is_file():
        raise GenerateError(f"missing {path}; the transport pins need it")
    by_path: dict[int, list[tuple[int, float, float, float]]] = {}
    for row in read_dbc(path):
        path_id = row.ints[1]
        if path_id not in TRANSPORT_PATHS:
            continue
        if row.ints[8] <= 0:
            continue
        by_path.setdefault(path_id, []).append(
            (row.ints[2], row.ints[3], row.floats[4], row.floats[5])
        )
    missing = set(TRANSPORT_PATHS) - set(by_path)
    if missing:
        raise GenerateError(f"no stopped nodes for transport paths: {sorted(missing)}")

    used: set[tuple[int, float, float]] = set()
    nodes: list[dict] = []
    for path_id, kind in TRANSPORT_PATHS.items():
        stops = sorted(by_path[path_id])
        if len(stops) != 2:
            raise GenerateError(f"path {path_id} has {len(stops)} stops, expected 2")
        (_, map_a, xa, ya), (_, map_b, xb, yb) = stops
        a = (map_a, round(xa, 1), round(ya, 1))
        b = (map_b, round(xb, 1), round(yb, 1))

        stations: list[tuple[tuple[int, float, float], str, str]] = []
        if a == b:
            names = SAME_POINT_ROUTES.get(path_id)
            if names is None:
                raise GenerateError(
                    f"path {path_id} has both stops at {a}; add it to SAME_POINT_ROUTES"
                )
            stations.append((a, names[0], names[1]))
        else:
            if path_id in SAME_POINT_ROUTES:
                raise GenerateError(
                    f"path {path_id} is listed in SAME_POINT_ROUTES but its stops differ"
                )
            for here, there in ((a, b), (b, a)):
                name = STATIONS.get(here)
                other = STATIONS.get(there)
                if name is None or other is None:
                    raise GenerateError(f"path {path_id}: no station entry for {here} or {there}")
                stations.append((here, name[0], other[0]))

        for coord, station_name, destination in stations:
            entry = STATIONS.get(coord)
            if entry is None:
                raise GenerateError(f"path {path_id}: no station entry for {coord}")
            zone_id = entry[1]
            used.add(coord)
            nodes.append(
                dict(
                    kind=kind,
                    zone_id=zone_id,
                    map_id=coord[0],
                    x=coord[1],
                    y=coord[2],
                    station=station_name,
                    destination=destination,
                )
            )

    unused = set(STATIONS) - used
    if unused:
        raise GenerateError(f"station entries no route uses: {sorted(unused)}")
    return nodes


def build(maps: Maps) -> dict[str, str]:
    bosses = []
    for zone_id, name, note, x, y in BOSSES:
        zone = next((z for z in maps.zones if z.key == zone_id and z.valid), None)
        if zone is None:
            raise GenerateError(f"no WorldMapArea bounds for boss zone {zone_id} ({name})")
        fractions = maps.fractions(zone.map_id, x, y, name, zone_id)
        bosses.append(dict(kind="boss", label=name, note=note, x=x, y=y, **fractions))

    services = []
    warps = sql_spawns(WARPWEAVER_SQL, len(WARPWEAVER_ZONES))
    for guid, zone_id, map_id, x, y in warps:
        # The SQL leaves zoneId 0, and the coordinate alone is ambiguous where zone bounds
        # overlap, so the zone must come from the GUID map. A new spawn without an entry here
        # would otherwise resolve to a neighbouring zone and produce a plausible wrong pin.
        zone_id = WARPWEAVER_ZONES.get(guid)
        if zone_id is None:
            raise GenerateError(f"Warpweaver spawn {guid} has no zone; add it to WARPWEAVER_ZONES")
        fractions = maps.fractions(map_id, x, y, f"Warpweaver {guid}", zone_id)
        services.append(
            dict(
                kind="warpweaver",
                label="Warpweaver",
                note="Transmogrifier",
                x=x,
                y=y,
                **fractions,
            )
        )
    for guid, zone_id, map_id, x, y in sql_spawns(CALLBOARD_SQL, CALLBOARD_COUNT):
        fractions = maps.fractions(map_id, x, y, "Call Board", zone_id)
        fractions["place"] = PLACE_OVERRIDES.get(guid, fractions["place"])
        services.append(
            dict(
                kind="callboard",
                label="Call Board",
                note="Custom quest board",
                x=x,
                y=y,
                **fractions,
            )
        )

    bosses.sort(key=lambda pin: (pin["cont"], pin["label"]))
    services.sort(key=lambda pin: (pin["kind"], pin["cont"], pin["place"]))

    portals = []
    for title, subtitle, map_id, x, y, zone_id, icon, destinations in PORTAL_ROOMS:
        fractions = maps.fractions(map_id, x, y, f"{title} {subtitle}", zone_id)
        portals.append(
            dict(
                kind="portal",
                label="Portal",
                note=subtitle,
                title=title,
                subtitle=subtitle,
                icon=icon,
                x=x,
                y=y,
                lines=[f"To {destination}" for destination in destinations],
                **fractions,
            )
        )

    transports = []
    for node in transport_nodes(maps):
        fractions = maps.fractions(
            node["map_id"], node["x"], node["y"], node["station"], node["zone_id"]
        )
        transports.append(
            dict(
                kind=node["kind"],
                label=node["station"],
                note="",
                title=node["station"],
                x=node["x"],
                y=node["y"],
                lines=[f"To {node['destination']}"],
                **fractions,
            )
        )

    for pin in bosses + services + portals + transports:
        pin["zones"] = [ZONE_PARENTS[pin["zone"]]] if pin["zone"] in ZONE_PARENTS else []

    portals.sort(key=lambda pin: (pin["cont"], pin["zone"], pin["subtitle"]))
    transports.sort(key=lambda pin: (pin["kind"], pin["cont"], pin["place"], pin["lines"][0]))
    # The parent zone names must be in zones.lua too, or the addon cannot match them.
    zone_ids = {pin["zone"] for pin in bosses + services + portals + transports}
    zone_ids |= {zone for pin in bosses + services + portals + transports for zone in pin["zones"]}
    hashes = {
        name: hashlib.sha256((maps.dbc / name).read_bytes()).hexdigest()
        for name in (
            "AreaTable.dbc",
            "DungeonMap.dbc",
            "TaxiPathNode.dbc",
            "WorldMapArea.dbc",
            "WorldMapTransforms.dbc",
        )
    }
    return {
        "bosses.lua": render("PinBosses", "Outdoor world bosses.", bosses, hashes),
        "services.lua": render(
            "PinServices", "Warpweaver and Call Board spawns from tracked SQL.", services, hashes
        ),
        "portals.lua": render("PinPortals", "Hub portal rooms.", portals, hashes),
        "transports.lua": render(
            "PinTransports", "Player ship and zeppelin station nodes.", transports, hashes
        ),
        "zones.lua": render_zones(maps, zone_ids, hashes),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dbc", default=DEFAULT_DBC, help="folder holding the client DBC files")
    parser.add_argument("--check", action="store_true", help="fail when a generated file is stale")
    args = parser.parse_args()

    try:
        rendered = build(Maps(Path(args.dbc).expanduser()))
    except GenerateError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    stale = []
    for name, text in rendered.items():
        path = DATA_DIR / name
        if path.exists() and path.read_text(encoding="utf-8") == text:
            continue
        stale.append(name)
        if not args.check:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
            print(f"wrote {path.relative_to(ROOT)}")

    if not args.check:
        return 0
    if stale:
        print(
            "error: generated pin data is stale: "
            + ", ".join(stale)
            + "; run python3 data/client-patches/map-pins/generate.py",
            file=sys.stderr,
        )
        return 1
    print("pin data up to date")
    return 0


if __name__ == "__main__":
    sys.exit(main())
