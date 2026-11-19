"""Unit tests for tools/dev/gen-addon-manifest.py.

Covers the pure functions only: DBC parsing, collapsing by (map, kind),
trigger picking, and manifest rendering. The database path is not tested.
"""

import importlib.util
import struct
import sys
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "gen-addon-manifest.py"
SPEC = importlib.util.spec_from_file_location("gen_addon_manifest", SCRIPT)
assert SPEC and SPEC.loader
gen = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = gen
SPEC.loader.exec_module(gen)


def write_dbc(records: list[tuple[int, str, int, int, int, int, int, int]]) -> bytes:
    """Synthetic LFGDungeons.dbc: (id, name, min, max, map, difficulty, type, expansion)."""
    # Fields: 0 id, 1 name offset, 19 max, 20 min, 23 map, 24 difficulty,
    # 26 type, 29 expansion; everything else zero.
    string_block = bytearray(b"\x00")
    packed = []
    for (row_id, name, min_level, max_level, map_id, difficulty, row_type,
         expansion) in records:
        offset = len(string_block)
        string_block += name.encode("utf-8") + b"\x00"
        fields = [0] * gen.FIELD_COUNT
        fields[0] = row_id
        fields[1] = offset
        fields[gen.F_MAX_LEVEL] = max_level
        fields[gen.F_MIN_LEVEL] = min_level
        fields[gen.F_MAP] = map_id
        fields[24] = difficulty
        fields[gen.F_TYPE] = row_type
        fields[gen.F_EXPANSION] = expansion
        packed.append(struct.pack(f"<{gen.FIELD_COUNT}i", *fields))
    header = struct.pack("<4s4I", b"WDBC", len(packed), gen.FIELD_COUNT,
                         gen.FIELD_COUNT * 4, len(string_block))
    return header + b"".join(packed) + bytes(string_block)


class ReadLfgDungeonsTest(unittest.TestCase):
    def test_parses_fields(self):
        data = write_dbc([(1, "Test Dungeon", 10, 20, 33, 0, 1, 0)])
        path = Path(__file__).with_name("lfgdungeons_fixture.dbc")
        path.write_bytes(data)
        try:
            rows = gen.read_lfg_dungeons(path)
        finally:
            path.unlink()
        self.assertEqual(rows, [{
            "id": 1, "name": "Test Dungeon", "min_level": 10, "max_level": 20,
            "map": 33, "difficulty": 0, "type": 1, "expansion": 0,
        }])

    def test_rejects_bad_magic(self):
        path = Path(__file__).with_name("bad_fixture.dbc")
        path.write_bytes(b"XXXX" + b"\x00" * 16)
        try:
            with self.assertRaises(gen.ManifestError):
                gen.read_lfg_dungeons(path)
        finally:
            path.unlink()


class CollapseTest(unittest.TestCase):
    def test_normal_and_heroic_merge_to_lowest_difficulty(self):
        rows = [
            {"id": 2, "name": "Heroic Test", "min_level": 80, "max_level": 80,
             "map": 33, "difficulty": 1, "type": 1, "expansion": 0},
            {"id": 1, "name": "Test Dungeon", "min_level": 10, "max_level": 20,
             "map": 33, "difficulty": 0, "type": 1, "expansion": 0},
        ]
        entries = gen.collapse_by_map(rows)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["name"], "Test Dungeon")
        self.assertEqual(entries[0]["difficulty"], 0)

    def test_shared_map_keeps_dungeon_and_raid(self):
        rows = [
            {"id": 1, "name": "Lower", "min_level": 58, "max_level": 65,
             "map": 229, "difficulty": 0, "type": 1, "expansion": 0},
            {"id": 2, "name": "Upper", "min_level": 60, "max_level": 83,
             "map": 229, "difficulty": 0, "type": 2, "expansion": 0},
        ]
        entries = gen.collapse_by_map(rows)
        self.assertEqual({entry["kind"] for entry in entries}, {"dungeon", "raid"})

    def test_zones_and_randoms_skipped(self):
        rows = [
            {"id": 1, "name": "Zone", "min_level": 0, "max_level": 60,
             "map": -1, "difficulty": 0, "type": 4, "expansion": 0},
            {"id": 2, "name": "Random", "min_level": 55, "max_level": 58,
             "map": 0, "difficulty": 0, "type": 6, "expansion": 0},
            {"id": 3, "name": "Real", "min_level": 10, "max_level": 20,
             "map": 36, "difficulty": 0, "type": 1, "expansion": 0},
        ]
        entries = gen.collapse_by_map(rows)
        self.assertEqual([entry["name"] for entry in entries], ["Real"])


class PickTriggerTest(unittest.TestCase):
    def test_prefers_entrance_name(self):
        triggers = [
            {"name": "Something (Exit)", "x": 1.0},
            {"name": "Something (Entrance)", "x": 2.0},
        ]
        self.assertEqual(gen.pick_trigger(triggers)["x"], 2.0)

    def test_falls_back_to_first(self):
        triggers = [{"name": "A", "x": 1.0}, {"name": "B", "x": 2.0}]
        self.assertEqual(gen.pick_trigger(triggers)["name"], "A")

    def test_empty(self):
        self.assertIsNone(gen.pick_trigger([]))


class RenderTest(unittest.TestCase):
    def test_renders_entry_with_tele_and_escaping(self):
        entries = [{
            "name": 'Quo"te \\ Map', "map": 36, "expansion": 0, "kind": "dungeon",
            "min_level": 19, "max_level": 25, "difficulty": 0,
            "tele": {"x": -16.4, "y": -383.07, "z": 61.78, "o": 1.86},
        }]
        text = "\n".join(gen.render_instances(entries))
        self.assertIn('name = "Quo\\"te \\\\ Map"', text)
        self.assertIn("map = 36", text)
        self.assertIn("x = -16.4000", text)

    def test_renders_gear_table(self):
        data = {"MAGE": [{"slot": "Head", "id": 50661, "name": 'Quo"te \\ Helm',
                          "ilvl": 277}]}
        text = "\n".join(gen.render_gear(data))
        self.assertIn("GMHelperGearData = {", text)
        self.assertIn("MAGE = {", text)
        self.assertIn('slot = "Head", id = 50661', text)
        self.assertIn('name = "Quo\\"te \\\\ Helm"', text)
        self.assertIn("ilvl = 277", text)

    def test_renders_combined_file(self):
        text = "\n".join(
            gen.render_instances([{
                "name": "Deadmines", "map": 36, "expansion": 0, "kind": "dungeon",
                "min_level": 19, "max_level": 25, "difficulty": 0,
                "tele": None,
            }]) + gen.render_gear({"MAGE": [{"slot": "Head", "id": 1,
                                             "name": "Test", "ilvl": 1}]}))
        self.assertIn("GMHelperInstancesData = {", text)
        self.assertIn("GMHelperGearData = {", text)


if __name__ == "__main__":
    unittest.main()
