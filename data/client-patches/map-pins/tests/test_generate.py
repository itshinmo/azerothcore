"""Offline checks for the map-pin generator's pure parts.

The DBC and SQL parsing is exercised against synthetic bytes, so these tests run without a
client and without the world database.

Run: python3 -m unittest discover -s data/client-patches/map-pins/tests -v
"""

from __future__ import annotations

import os
import struct
import sys
import tempfile
import types
import unittest
import unittest.mock
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import generate  # noqa: E402


def write_dbc(path: Path, rows: list[list[int]], strings: list[str]) -> None:
    """Write a minimal WDBC file whose fields are all integers."""
    table = b"\0"
    for text in strings:
        table += text.encode("utf-8") + b"\0"
    fields = len(rows[0]) if rows else 1
    body = b"".join(struct.pack(f"<{fields}i", *row) for row in rows)
    header = struct.pack("<4sIIII", b"WDBC", len(rows), fields, fields * 4, len(table))
    path.write_bytes(header + body + table)


def write_map_dbc(path: Path, rows: list[list[int]], strings: list[str]) -> None:
    write_dbc(path, rows, strings)


def map_area_row(
    key: int,
    map_id: int,
    name_offset: int,
    *,
    y_max: float,
    y_min: float,
    x_max: float,
    x_min: float,
    display: int = -1,
    floor: int = 0,
) -> list[int]:
    """One WorldMapArea row with the float fields packed as their int bit patterns."""
    row = [0] * 11
    row[0] = key
    row[1] = map_id
    row[2] = key
    row[3] = name_offset
    row[4] = struct.unpack("<i", struct.pack("<f", y_max))[0]
    row[5] = struct.unpack("<i", struct.pack("<f", y_min))[0]
    row[6] = struct.unpack("<i", struct.pack("<f", x_max))[0]
    row[7] = struct.unpack("<i", struct.pack("<f", x_min))[0]
    row[8] = display
    row[9] = floor
    return row


def transform_row(
    region: int, map_id: int, new_map: int, offset_x: float, offset_y: float
) -> list[int]:
    row = [0] * 10
    row[0] = region
    row[1] = map_id
    row[6] = new_map
    row[7] = struct.unpack("<i", struct.pack("<f", offset_x))[0]
    row[8] = struct.unpack("<i", struct.pack("<f", offset_y))[0]
    return row


class ReadDbcTest(unittest.TestCase):
    def test_reads_int_and_float_views_of_each_field(self):
        with self.tmp() as folder:
            path = folder / "x.dbc"
            write_dbc(path, [[1, 2, 3]], [""])
            rows = generate.read_dbc(path)
            self.assertEqual(rows[0].ints, (1, 2, 3))
            self.assertEqual(len(rows[0].floats), 3)

    def test_rejects_a_non_wdbc_file(self):
        with self.tmp() as folder:
            path = folder / "x.dbc"
            path.write_bytes(b"not a dbc")
            with self.assertRaises(generate.GenerateError):
                generate.read_dbc(path)

    def test_rejects_a_truncated_file(self):
        with self.tmp() as folder:
            path = folder / "x.dbc"
            write_dbc(path, [[1, 2]], [""])
            raw = path.read_bytes()
            path.write_bytes(raw[:-4])
            with self.assertRaises(generate.GenerateError):
                generate.read_dbc(path)

    def test_strings_are_read_from_the_string_block(self):
        with self.tmp() as folder:
            path = folder / "x.dbc"
            write_dbc(path, [[1, 1]], ["Duskwood", "Elwynn"])
            table = generate.dbc_strings(path)
            self.assertEqual(generate.string_at(table, 1), "Duskwood")
            self.assertEqual(generate.string_at(table, 10), "Elwynn")
            with self.assertRaises(generate.GenerateError):
                generate.string_at(table, 999)

    def tmp(self):
        import tempfile

        class Folder:
            def __enter__(self):
                self.path = Path(tempfile.mkdtemp())
                return self.path

            def __exit__(self, *args):
                import shutil

                shutil.rmtree(self.path)

        return Folder()


class MapsTest(unittest.TestCase):
    """The projection math, against synthetic DBCs shaped like the real ones.

    This is the code that put Silvermoon and the Exodar in the ocean; it had no Python coverage.
    """

    def build(self, folder: Path, *, with_dungeon: bool = False) -> Path:
        dbc = folder / "dbc"
        dbc.mkdir()
        strings = ["", "Kalimdor", "Azeroth", "Expansion01", "Northrend", "Dalaran",
                   "SilvermoonCity", "TheExodar", "Elwynn"]
        offsets = {}
        cursor = 0
        for text in strings:
            offsets[text or ""] = cursor
            cursor += len(text.encode()) + 1

        area_rows = []
        for area_id, name in ((10, "Elwynn"), (3487, "SilvermoonCity"), (3557, "TheExodar"),
                              (4395, "Dalaran")):
            row = [0] * 36
            row[0] = area_id
            row[11] = offsets[name]
            area_rows.append(row)
        write_dbc(dbc / "AreaTable.dbc", area_rows, strings)

        # Continent rows come first, in client order: 1 Kalimdor, 2 Azeroth, 3 Outland,
        # 4 Northrend. Then two plain zones and two map-530 zones that display on 0 and 1.
        zones = [
            map_area_row(0, 1, offsets["Kalimdor"], y_max=17066.6, y_min=-19733.2,
                         x_max=12799.9, x_min=-11733.3),
            map_area_row(0, 0, offsets["Azeroth"], y_max=18172.0, y_min=-22569.2,
                         x_max=11176.3, x_min=-15973.3),
            map_area_row(0, 530, offsets["Expansion01"], y_max=12996.0, y_min=-4468.0,
                         x_max=5821.4, x_min=-5821.4),
            map_area_row(0, 571, offsets["Northrend"], y_max=9217.0, y_min=-8534.0,
                         x_max=10593.0, x_min=-1241.0),
            map_area_row(10, 0, offsets["Elwynn"], y_max=100.0, y_min=-100.0,
                         x_max=200.0, x_min=-200.0),
            map_area_row(3487, 530, offsets["SilvermoonCity"], y_max=-6400.8, y_min=-7612.2,
                         x_max=10153.7, x_min=9346.9, display=0),
            map_area_row(3557, 530, offsets["TheExodar"], y_max=-11066.4, y_min=-12123.1,
                         x_max=-3609.7, x_min=-4314.4, display=1),
            map_area_row(4395, 571, offsets["Dalaran"], y_max=0.0, y_min=0.0,
                         x_max=0.0, x_min=0.0, floor=27),
        ]
        write_dbc(dbc / "WorldMapArea.dbc", zones, strings)

        transforms = [
            transform_row(2, 530, 0, -2400.0, 2400.0),
            transform_row(3, 530, 1, 10133.333, 17600.0),
        ]
        write_dbc(dbc / "WorldMapTransforms.dbc", transforms, strings)

        if with_dungeon:
            # DungeonMap row: id, map, floor, then yMin, yMax, xMin, xMax.
            row = [0] * 8
            row[0] = 27
            row[1] = 571
            row[2] = 1
            for index, value in enumerate((222.5, 1052.5, 5513.3, 6066.7), start=3):
                row[index] = struct.unpack("<i", struct.pack("<f", value))[0]
            write_dbc(dbc / "DungeonMap.dbc", [row], strings)
        else:
            write_dbc(dbc / "DungeonMap.dbc", [[0] * 8], strings)
        return dbc

    def test_continent_order_is_the_client_order(self):
        with tempfile.TemporaryDirectory() as folder:
            maps = generate.Maps(self.build(Path(folder)))
        self.assertEqual(maps.continents, {1: 1, 0: 2, 530: 3, 571: 4})

    def test_plain_zone_uses_its_own_bounds(self):
        with tempfile.TemporaryDirectory() as folder:
            maps = generate.Maps(self.build(Path(folder)))
            pin = maps.fractions(0, 100.0, 50.0, "Elwynn", 10)
        # mx = (yMax - y) / (yMax - yMin) = (100 - 50) / 200
        self.assertAlmostEqual(pin["mx"], 0.25, places=4)
        # my = (xMax - x) / (xMax - xMin) = (200 - 100) / 400
        self.assertAlmostEqual(pin["my"], 0.25, places=4)
        self.assertEqual(pin["cont"], 2, "map 0 is the second continent")

    def test_map_530_zone_on_eastern_kingdoms_adds_the_offset(self):
        with tempfile.TemporaryDirectory() as folder:
            maps = generate.Maps(self.build(Path(folder)))
            pin = maps.fractions(530, 9870.2, -7442.9, "Silvermoon", 3487)
        # Zone fraction is raw: the offset must not touch it.
        self.assertAlmostEqual(pin["mx"], 0.8602, places=4)
        self.assertAlmostEqual(pin["my"], 0.3514, places=4)
        # Continent fraction is offset first: x 9870.2 - 2400, y -7442.9 + 2400.
        expected_mx = (18172.0 - (-5042.9)) / (18172.0 + 22569.2)
        expected_my = (11176.3 - 7470.2) / (11176.3 + 15973.3)
        self.assertAlmostEqual(pin["cx"], round(expected_mx, 4), places=4)
        self.assertAlmostEqual(pin["cy"], round(expected_my, 4), places=4)
        self.assertEqual(pin["cont"], 2)

    def test_map_530_zone_on_kalimdor_adds_its_own_offset(self):
        with tempfile.TemporaryDirectory() as folder:
            maps = generate.Maps(self.build(Path(folder)))
            pin = maps.fractions(530, -3931.7, -11625.6, "Exodar", 3557)
        expected_mx = (17066.6 - (-11625.6 + 17600.0)) / (17066.6 + 19733.2)
        expected_my = (12799.9 - (-3931.7 + 10133.333)) / (12799.9 + 11733.3)
        self.assertAlmostEqual(pin["cx"], round(expected_mx, 4), places=4)
        self.assertAlmostEqual(pin["cy"], round(expected_my, 4), places=4)
        self.assertEqual(pin["cont"], 1, "map 1 is Kalimdor")

    def test_offset_direction_would_be_caught(self):
        """Subtracting the offset instead of adding it must not reproduce the goldens."""
        with tempfile.TemporaryDirectory() as folder:
            maps = generate.Maps(self.build(Path(folder)))
            pin = maps.fractions(530, 9870.2, -7442.9, "Silvermoon", 3487)
        wrong = (18172.0 - (-7442.9 - 2400.0)) / (18172.0 + 22569.2)
        self.assertNotAlmostEqual(pin["cx"], round(wrong, 4), places=4)

    def test_dalaran_falls_back_to_dungeon_map_bounds(self):
        with tempfile.TemporaryDirectory() as folder:
            maps = generate.Maps(self.build(Path(folder), with_dungeon=True))
            pin = maps.fractions(571, 5842.8, 721.8, "Dalaran", 4395)
        self.assertAlmostEqual(pin["mx"], 0.3984, places=4)
        self.assertAlmostEqual(pin["my"], 0.4046, places=4)
        self.assertEqual(pin["cont"], 4)

    def test_dalaran_without_dungeon_bounds_is_an_error(self):
        with tempfile.TemporaryDirectory() as folder:
            maps = generate.Maps(self.build(Path(folder)))
            with self.assertRaises(generate.GenerateError):
                maps.fractions(571, 5842.8, 721.8, "Dalaran", 4395)

    def test_unknown_zone_id_is_an_error(self):
        with tempfile.TemporaryDirectory() as folder:
            maps = generate.Maps(self.build(Path(folder)))
            with self.assertRaises(generate.GenerateError):
                maps.fractions(0, 0.0, 0.0, "Nowhere", 9999)

    def test_an_offset_that_leaves_the_map_is_an_error(self):
        with tempfile.TemporaryDirectory() as folder:
            maps = generate.Maps(self.build(Path(folder)))
            with self.assertRaises(generate.GenerateError):
                maps.fractions(530, -30000.0, -30000.0, "Off map", 3487)


class SqlSpawnTest(unittest.TestCase):
    SQL = """-- header
INSERT INTO `creature` (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`,
  `position_x`, `position_y`, `position_z`)
VALUES
(5400001, @Entry, 0, 1519, 1519, 1, -8829.3, 598.9, 95.8),
(5400008, @Entry, 530, 3487, 3487, 1, 9870.2, -7442.9, 13.7);
"""

    def test_reads_guid_zone_map_and_position(self):
        with self.tmp_file(self.SQL) as path:
            rows = generate.sql_spawns(path, 2)
        self.assertEqual(
            rows,
            [(5400001, 1519, 0, -8829.3, 598.9), (5400008, 3487, 530, 9870.2, -7442.9)],
        )

    def test_a_short_row_count_is_an_error(self):
        with self.tmp_file(self.SQL) as path:
            with self.assertRaises(generate.GenerateError) as caught:
                generate.sql_spawns(path, 3)
        self.assertIn("expected 3", str(caught.exception))

    def test_an_unparseable_row_is_an_error_not_a_skip(self):
        sql = self.SQL.replace("(5400008, @Entry, 530, 3487, 3487, 1, 9870.2, -7442.9, 13.7)",
                               "(5400008, @Entry, 530, 3487, 3487, 1, not-a-number, -7442.9, 13.7)")
        with self.tmp_file(sql) as path:
            with self.assertRaises(generate.GenerateError):
                generate.sql_spawns(path, 2)

    def test_ignores_statements_without_a_position(self):
        sql = "INSERT INTO `npc_text` (`ID`, `text0_0`) VALUES\n(1, 'hello');\n"
        with self.tmp_file(sql) as path:
            self.assertEqual(generate.sql_spawns(path, 0), [])

    def tmp_file(self, text):
        import tempfile

        class File:
            def __enter__(self):
                handle = tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False)
                handle.write(text)
                handle.close()
                self.path = Path(handle.name)
                return self.path

            def __exit__(self, *args):
                self.path.unlink()

        return File()


class RenderTest(unittest.TestCase):
    def test_render_writes_a_named_table_with_every_field(self):
        text = generate.render(
            "PinBosses",
            "Bosses.",
            [
                {
                    "kind": "boss",
                    "zone": 10,
                    "place": "Duskwood",
                    "label": "Taerar",
                    "note": "Classic world boss",
                    "x": -10428.8,
                    "y": -392.2,
                    "mx": 0.4539,
                    "my": 0.3956,
                    "cont": 2,
                    "cx": 0.4557,
                    "cy": 0.7958,
                }
            ],
            {"WorldMapArea.dbc": "deadbeef"},
        )
        self.assertIn("ns.PinBosses = {", text)
        self.assertIn("WorldMapArea.dbc: sha256 deadbeef", text)
        self.assertIn('label = "Taerar"', text)
        self.assertIn("mx = 0.4539", text)
        self.assertIn("cy = 0.7958", text)
        self.assertTrue(text.endswith("}\n"))

    def test_render_is_deterministic(self):
        pins = [
            dict(
                kind="boss",
                zone=10,
                place="Duskwood",
                label="Taerar",
                note="Classic world boss",
                x=1.0,
                y=2.0,
                mx=0.1,
                my=0.2,
                cont=2,
                cx=0.3,
                cy=0.4,
            )
        ]
        self.assertEqual(
            generate.render("PinBosses", "Bosses.", pins, {}),
            generate.render("PinBosses", "Bosses.", pins, {}),
        )


def write_taxi_dbc(path: Path, rows: list[tuple]) -> None:
    """Write a TaxiPathNode.dbc.

    Row layout: id, path, index, map, x, y, z, flags, delay, arrival, departure. Fields 4, 5, 6
    and 8 are floats; the rest are ints.
    """
    floats = {4, 5, 6, 8}
    packed = []
    for row in rows:
        values = []
        for index, value in enumerate(row):
            if index in floats:
                values.append(struct.unpack("<i", struct.pack("<f", float(value)))[0])
            else:
                values.append(int(value))
        packed.append(values)
    write_dbc(path, packed, [""])


class ZoneParentTest(unittest.TestCase):
    """Every curated parent must really overlap its city on the same map.

    Geometric containment is not the rule (each city's bounds overlap three outdoor zones), so
    this asserts the curated pair differently: the parent must be on the same map, it must cover
    most of the city rectangle, and the city must not fall entirely outside it. Orgrimmar is the
    reason a tolerance is needed at all: its auction house stands on Durotar's eastern edge, where
    only half the city rectangle overlaps the zone.
    """

    def maps(self):
        path = Path(os.environ.get("ACORE_DATA", os.path.expanduser("~/wow/Data/dbc")))
        return generate.Maps(path)

    def test_curated_parents_are_real_zones(self):
        maps = self.maps()
        by_key = {zone.key: zone for zone in maps.zones}
        for city, parent in generate.ZONE_PARENTS.items():
            self.assertIn(city, by_key, f"city zone {city} is not in WorldMapArea")
            self.assertIn(parent, by_key, f"parent zone {parent} is not in WorldMapArea")
            self.assertEqual(by_key[city].map_id, by_key[parent].map_id,
                             "a city and its parent must share a map")

    def test_every_parent_overlaps_most_of_its_city(self):
        maps = self.maps()
        by_key = {zone.key: zone for zone in maps.zones}
        for city, parent in generate.ZONE_PARENTS.items():
            zone, city_zone = by_key[parent], by_key[city]
            ox = max(0.0, min(max(city_zone.x_min, city_zone.x_max), max(zone.x_min, zone.x_max))
                      - max(min(city_zone.x_min, city_zone.x_max), min(zone.x_min, zone.x_max)))
            oy = max(0.0, min(max(city_zone.y_min, city_zone.y_max), max(zone.y_min, zone.y_max))
                      - max(min(city_zone.y_min, city_zone.y_max), min(zone.y_min, zone.y_max)))
            city_area = abs(city_zone.x_max - city_zone.x_min) * abs(city_zone.y_max - city_zone.y_min)
            self.assertGreater(city_area, 0, f"{city} has zero bounds")
            coverage = (ox * oy) / city_area
            self.assertGreater(
                coverage, 0.4,
                f"{maps.map_zone_name(city)} overlaps only {coverage:.0%} of "
                f"{maps.map_zone_name(parent)}",
            )

    def test_every_serviced_city_has_a_parent(self):
        # The pins that need a parent are the cities the project actually services. Comparing the
        # exact set stops a deleted entry from silently passing every other assertion.
        self.assertEqual(
            set(generate.ZONE_PARENTS),
            {1519, 1497, 1537, 1637, 1638, 1657, 3487, 3557, 3703},
            "every serviced capital must have a curated parent zone",
        )

    def test_dalaran_has_no_parent(self):
        self.assertNotIn(4395, generate.ZONE_PARENTS,
                         "Dalaran is its own micro-map and must not draw on a Northrend zone")

    def test_every_parent_zone_is_generated_into_zones_lua(self):
        # The addon resolves a parent id through zones.lua, so a missing name means a pin that
        # never draws on the region map.
        text = (Path(__file__).resolve().parents[1] / "src" / "WorldMapPins" / "data" / "zones.lua")
        generated = text.read_text()
        for parent in generate.ZONE_PARENTS.values():
            self.assertIn(f"[{parent}] =", generated, f"zone {parent} is missing from zones.lua")


class PortalRoomsTest(unittest.TestCase):
    def test_twelve_rooms_with_icons_and_destinations(self):
        self.assertEqual(len(generate.PORTAL_ROOMS), 12)
        for title, subtitle, _map, _x, _y, zone, icon, destinations in generate.PORTAL_ROOMS:
            self.assertTrue(title and subtitle, "every room names a city and a place")
            self.assertTrue(zone > 0, "every room has a zone id")
            self.assertTrue(icon.startswith("Spell_Arcane_Portal"), icon)
            self.assertGreaterEqual(len(destinations), 1, subtitle)

    def test_the_shattrath_room_lists_eight_capitals(self):
        room = next(room for room in generate.PORTAL_ROOMS if room[1] == "Terrace of Light")
        self.assertEqual(
            room[7],
            ("Stormwind", "Ironforge", "Darnassus", "The Exodar", "Orgrimmar", "Undercity",
             "Thunder Bluff", "Silvermoon City"),
        )

    def test_eight_blast_lands_portals_one_per_capital(self):
        blasted = [room for room in generate.PORTAL_ROOMS if "Blasted Lands" in room[1]]
        self.assertEqual(len(blasted), 8)
        self.assertEqual(
            sorted(room[0] for room in blasted),
            ["Darnassus", "Ironforge", "Orgrimmar", "Silvermoon City", "Stormwind City",
             "The Exodar", "Thunder Bluff", "Undercity"],
        )


class TransportNodesTest(unittest.TestCase):
    ROUTES = {101: "ship", 102: "zeppelin"}

    def build(self, folder: Path, rows: list[tuple]) -> Path:
        dbc = folder / "dbc"
        dbc.mkdir()
        write_taxi_dbc(dbc / "TaxiPathNode.dbc", rows)
        return dbc

    def nodes(self, dbc: Path, routes: dict, stations: dict, same: dict | None = None):
        with unittest.mock.patch.dict(generate.TRANSPORT_PATHS, routes, clear=True), \
                unittest.mock.patch.dict(generate.STATIONS, stations, clear=True), \
                unittest.mock.patch.dict(generate.SAME_POINT_ROUTES, same or {}, clear=True):
            return generate.transport_nodes(types.SimpleNamespace(dbc=dbc))

    def test_two_stops_produce_two_pins_naming_each_other(self):
        rows = [
            (1, 101, 0, 0, -100.0, 200.0, 10.0, 0, 60, 0, 0),
            (2, 101, 1, 0, -50.0, 250.0, 10.0, 0, 60, 0, 0),
            (3, 102, 0, 1, 300.0, 400.0, 5.0, 0, 60, 0, 0),
            (4, 102, 1, 1, 350.0, 450.0, 5.0, 0, 60, 0, 0),
        ]
        stations = {
            (0, -100.0, 200.0): ("Alpha", 10),
            (0, -50.0, 250.0): ("Beta", 10),
            (1, 300.0, 400.0): ("Gamma", 20),
            (1, 350.0, 450.0): ("Delta", 20),
        }
        with tempfile.TemporaryDirectory() as folder:
            nodes = self.nodes(self.build(Path(folder), rows), self.ROUTES, stations)
        by_title = {node["station"]: node for node in nodes}
        self.assertEqual(len(nodes), 4)
        self.assertEqual(by_title["Alpha"]["destination"], "Beta")
        self.assertEqual(by_title["Beta"]["destination"], "Alpha")
        self.assertEqual(by_title["Gamma"]["kind"], "zeppelin")
        self.assertEqual(by_title["Delta"]["destination"], "Gamma")
        self.assertEqual(by_title["Alpha"]["zone_id"], 10)

    def test_a_stop_without_delay_is_not_a_station(self):
        rows = [
            (1, 101, 0, 0, -100.0, 200.0, 10.0, 0, 60, 0, 0),
            (2, 101, 1, 0, 0.0, 0.0, 10.0, 0, 0, 0, 0),
            (3, 101, 2, 0, -50.0, 250.0, 10.0, 0, 60, 0, 0),
        ]
        stations = {
            (0, -100.0, 200.0): ("Alpha", 10),
            (0, -50.0, 250.0): ("Beta", 10),
        }
        with tempfile.TemporaryDirectory() as folder:
            nodes = self.nodes(
                self.build(Path(folder), rows), {101: "ship"}, stations
            )
        self.assertEqual(len(nodes), 2, "the delay-free node is a waypoint, not a station")

    def test_one_stop_must_be_a_waypoint_not_a_station(self):
        rows = [
            (1, 101, 0, 0, 0.0, 0.0, 0.0, 0, 60, 0, 0),
            (2, 101, 1, 0, 10.0, 10.0, 0.0, 0, 60, 0, 0),
            (3, 101, 2, 0, 20.0, 20.0, 0.0, 0, 60, 0, 0),
        ]
        with tempfile.TemporaryDirectory() as folder:
            dbc = self.build(Path(folder), rows)
            with self.assertRaises(generate.GenerateError) as caught:
                self.nodes(dbc, {101: "ship"}, {
                    (0, 0.0, 0.0): ("A", 10),
                    (0, 10.0, 10.0): ("B", 10),
                    (0, 20.0, 20.0): ("C", 10),
                })
        self.assertIn("expected 2", str(caught.exception))

    def test_shared_coordinate_route_becomes_one_pin(self):
        rows = [
            (1, 101, 0, 0, 5.0, 5.0, 0.0, 0, 60, 0, 0),
            (2, 101, 1, 0, 5.0, 5.0, 0.0, 0, 60, 0, 0),
        ]
        with tempfile.TemporaryDirectory() as folder:
            nodes = self.nodes(
                self.build(Path(folder), rows),
                {101: "zeppelin"},
                {(0, 5.0, 5.0): ("Here", 10)},
                {101: ("Here", "There")},
            )
        self.assertEqual(len(nodes), 1)
        self.assertEqual(nodes[0]["station"], "Here")
        self.assertEqual(nodes[0]["destination"], "There")

    def test_a_shared_coordinate_route_must_be_declared(self):
        rows = [
            (1, 101, 0, 0, 5.0, 5.0, 0.0, 0, 60, 0, 0),
            (2, 101, 1, 0, 5.0, 5.0, 0.0, 0, 60, 0, 0),
        ]
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(generate.GenerateError) as caught:
                self.nodes(self.build(Path(folder), rows), {101: "ship"},
                           {(0, 5.0, 5.0): ("Here", 10)})
        self.assertIn("SAME_POINT_ROUTES", str(caught.exception))

    def test_a_station_without_a_name_is_an_error(self):
        rows = [
            (1, 101, 0, 0, 0.0, 0.0, 0.0, 0, 60, 0, 0),
            (2, 101, 1, 0, 10.0, 10.0, 0.0, 0, 60, 0, 0),
        ]
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(generate.GenerateError):
                self.nodes(self.build(Path(folder), rows), {101: "ship"},
                           {(0, 0.0, 0.0): ("Only one", 10)})

    def test_an_unused_station_entry_is_an_error(self):
        rows = [
            (1, 101, 0, 0, 0.0, 0.0, 0.0, 0, 60, 0, 0),
            (2, 101, 1, 0, 10.0, 10.0, 0.0, 0, 60, 0, 0),
        ]
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(generate.GenerateError) as caught:
                self.nodes(self.build(Path(folder), rows), {101: "ship"}, {
                    (0, 0.0, 0.0): ("A", 10),
                    (0, 10.0, 10.0): ("B", 10),
                    (0, 99.0, 99.0): ("Stale", 10),
                })
        self.assertIn("no route uses", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
