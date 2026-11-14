#!/usr/bin/env python3
"""Unit tests for tools/dev/world-export.py."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "world-export.py"
SPEC = importlib.util.spec_from_file_location("world_export", SCRIPT)
assert SPEC and SPEC.loader
export = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = export
SPEC.loader.exec_module(export)


class BucketTest(unittest.TestCase):
    def test_letters_and_digits(self):
        self.assertEqual(export.bucket_for("Baron Longshore"), "b")
        self.assertEqual(export.bucket_for(" 7: The Thing"), "7")

    def test_unknown_first_character_falls_back(self):
        self.assertEqual(export.bucket_for(""), "_")
        self.assertEqual(export.bucket_for("[PH] test"), "_")


class ObjectiveTest(unittest.TestCase):
    def test_maps_slots_to_kinds(self):
        row = ["0"] * 29
        row[0] = "57"
        row[6] = "531"
        row[10] = "15"
        row[7] = "-202"
        row[11] = "3"
        row[14] = "2589"
        row[20] = "10"
        objectives = export.parse_quest_objectives(row)
        self.assertEqual(objectives, [
            {"kind": "creature", "id": 531, "count": 15},
            {"kind": "gameobject", "id": 202, "count": 3},
            {"kind": "item", "id": 2589, "count": 10},
        ])


class SpawnTest(unittest.TestCase):
    def test_small_set_is_one_file(self):
        points = [{"map": 0, "spawnId": index} for index in range(3)]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parts = export.write_spawns(root, "npc", 5, points, "2026-01-01T00:00:00Z")
            self.assertEqual(parts, [])
            payload = json.loads((root / "spawns/npc/5.json").read_text())
            self.assertEqual(len(payload["points"]), 3)

    def test_large_set_splits_per_map(self):
        points = [{"map": 0, "spawnId": index} for index in range(400)]
        points += [{"map": 1, "spawnId": 1000 + index} for index in range(300)]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parts = export.write_spawns(root, "npc", 7, points, "2026-01-01T00:00:00Z")
            self.assertEqual(parts, ["spawns/npc/7-0.json", "spawns/npc/7-1.json"])
            canonical = json.loads((root / "spawns/npc/7.json").read_text())
            self.assertEqual(canonical["parts"], parts)
            first = json.loads((root / parts[0]).read_text())
            self.assertEqual(len(first["points"]), 400)


class WriteJsonTest(unittest.TestCase):
    def test_output_is_stable_and_sorted(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "nested" / "doc.json"
            export.write_json(path, {"b": 1, "a": {"d": 2, "c": 3}})
            first = path.read_text()
            export.write_json(path, {"a": {"c": 3, "d": 2}, "b": 1})
            self.assertEqual(first, path.read_text())
            self.assertTrue(first.endswith("\n"))


class PrepareOutputTest(unittest.TestCase):
    def test_refuses_non_empty_without_force(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "export"
            output.mkdir()
            (output / "keep.txt").write_text("x")
            with self.assertRaises(export.ExportError):
                export.prepare_output(output, force=False)

    def test_refuses_force_without_meta(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "export"
            output.mkdir()
            (output / "keep.txt").write_text("x")
            with self.assertRaises(export.ExportError):
                export.prepare_output(output, force=True)

    def test_force_accepts_an_export_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "export"
            output.mkdir()
            export.write_json(output / "meta.json", {"schemaVersion": export.SCHEMA_VERSION})
            temp = export.prepare_output(output, force=True)
            self.assertTrue(temp.is_dir())
            self.assertTrue(str(temp).endswith(".tmp"))

    def test_commit_replaces_the_old_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "export"
            output.mkdir()
            temp = export.prepare_output(output, force=False)
            export.write_json(temp / "meta.json", {"schemaVersion": export.SCHEMA_VERSION})
            export.commit_output(output, temp)
            self.assertTrue((output / "meta.json").exists())
            self.assertFalse(temp.exists())


if __name__ == "__main__":
    unittest.main()
