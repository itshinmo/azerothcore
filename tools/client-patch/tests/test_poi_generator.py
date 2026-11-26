"""Tests for the map-POI generator header, bounds guards and zone resolution."""

from __future__ import annotations

import struct
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "data" / "client-patches" / "map-poi"))

import generate_poi_data  # noqa: E402


def float_field(value: float) -> int:
    return struct.unpack("<I", struct.pack("<f", value))[0]


def world_map_row(area: int, y_max: float, y_min: float, x_max: float, x_min: float) -> list[int]:
    return [
        0,
        0,
        area,
        0,
        float_field(y_max),
        float_field(y_min),
        float_field(x_max),
        float_field(x_min),
        0,
        0,
        0,
    ]


def area(name: str, zone: int = 0) -> dict:
    return {"map": 0, "zone": zone, "flags": 0, "name": name}


class PoiGeneratorTests(unittest.TestCase):
    def test_world_map_area_field_count_is_asserted(self):
        with self.assertRaises(SystemExit):
            generate_poi_data.zone_bounds([], b"", 9, {})

    def test_inverted_bounds_are_skipped(self):
        """A row with inverted bounds is a sub-area with no map of its own, not a fatal error."""
        rows = [world_map_row(1519, 50.0, 100.0, 10.0, -10.0)]
        bounds = generate_poi_data.zone_bounds(rows, b"", 11, {})
        self.assertEqual(bounds, {})

    def test_valid_bounds_are_accepted(self):
        rows = [world_map_row(1519, 100.0, 50.0, 10.0, -10.0)]
        bounds = generate_poi_data.zone_bounds(rows, b"", 11, {1519: area("Stormwind City")})
        self.assertEqual(bounds[1519]["yMax"], 100.0)
        self.assertEqual(bounds[1519]["yMin"], 50.0)
        self.assertEqual(bounds[1519]["xMax"], 10.0)
        self.assertEqual(bounds[1519]["xMin"], -10.0)
        self.assertEqual(bounds[1519]["name"], "Stormwind City")

    def test_first_row_wins_for_duplicate_zones(self):
        rows = [
            world_map_row(1519, 100.0, 50.0, 10.0, -10.0),
            world_map_row(1519, 200.0, 150.0, 20.0, 0.0),
        ]
        bounds = generate_poi_data.zone_bounds(rows, b"", 11, {})
        self.assertEqual(bounds[1519]["yMax"], 100.0)

    def test_resolve_zone_prefers_the_spawns_own_zone(self):
        bounds = {1519: {"name": "Stormwind City"}}
        areas = {4129: area("Stormwind City", zone=0)}
        self.assertEqual(generate_poi_data.resolve_zone(4129, 1519, areas, bounds), 1519)

    def test_resolve_zone_falls_back_to_the_parent_zone(self):
        bounds = {1519: {"name": "Stormwind City"}}
        areas = {4411: area("Stormwind Harbor", zone=1519)}
        self.assertEqual(generate_poi_data.resolve_zone(4411, 0, areas, bounds), 1519)

    def test_resolve_zone_returns_none_when_nothing_is_drawable(self):
        bounds = {1519: {"name": "Stormwind City"}}
        areas = {999: area("Somewhere", zone=888)}
        self.assertIsNone(generate_poi_data.resolve_zone(999, 777, areas, bounds))

    def test_transport_dock_splits_route_and_faction(self):
        route, faction = generate_poi_data.transport_dock(
            'Grom\'gol Base Camp, Stranglethorn Vale and Orgrimmar, Durotar (Zeppelin, Horde ("The Iron Eagle"))'
        )
        self.assertEqual(faction, "horde")
        self.assertTrue(route.startswith("Grom'gol Base Camp"))
        self.assertNotIn("Zeppelin", route)

    def test_transport_dock_reads_alliance(self):
        _, faction = generate_poi_data.transport_dock(
            'Auberdine, Darkshore and Stormwind Harbor (Boat, Alliance ("The Bravery"))'
        )
        self.assertEqual(faction, "alliance")

    def test_transport_dock_defaults_to_neutral(self):
        _, faction = generate_poi_data.transport_dock("Somewhere and Elsewhere")
        self.assertEqual(faction, "neutral")


if __name__ == "__main__":
    unittest.main()
