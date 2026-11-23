"""Tests for the map-POI generator header and bounds guards."""

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


class PoiGeneratorTests(unittest.TestCase):
    def test_world_map_area_field_count_is_asserted(self):
        with self.assertRaises(SystemExit):
            generate_poi_data.zone_bounds([], 9)

    def test_inverted_bounds_exit_nonzero(self):
        rows = [world_map_row(1519, 50.0, 100.0, 10.0, -10.0)]
        with self.assertRaises(SystemExit):
            generate_poi_data.zone_bounds(rows, 11)

    def test_valid_bounds_are_accepted(self):
        rows = [world_map_row(1519, 100.0, 50.0, 10.0, -10.0)]
        bounds = generate_poi_data.zone_bounds(rows, 11)
        self.assertEqual(bounds[1519]["yMax"], 100.0)
        self.assertEqual(bounds[1519]["yMin"], 50.0)
        self.assertEqual(bounds[1519]["xMax"], 10.0)
        self.assertEqual(bounds[1519]["xMin"], -10.0)


if __name__ == "__main__":
    unittest.main()
