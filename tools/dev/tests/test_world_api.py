#!/usr/bin/env python3
"""Unit tests for tools/dev/world-api.py."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "world-api.py"
SPEC = importlib.util.spec_from_file_location("world_api", SCRIPT)
assert SPEC and SPEC.loader
api = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = api
SPEC.loader.exec_module(api)


def make_export(root: Path) -> None:
    (root / "npc").mkdir(parents=True)
    (root / "search").mkdir(parents=True)
    meta = {"schemaVersion": 1, "generatedAt": "2026-01-01T00:00:00Z",
            "counts": {"npc": 2, "item": 0, "quest": 0, "object": 0}}
    (root / "meta.json").write_text(json.dumps(meta))
    npc = {"id": 3467, "name": "Baron Longshore", "schemaVersion": 1,
           "generatedAt": "2026-01-01T00:00:00Z"}
    (root / "npc" / "3467.json").write_text(json.dumps(npc))
    (root / "search" / "b.json").write_text(json.dumps({
        "results": [{"type": "npc", "id": 3467, "name": "Baron Longshore"},
                    {"type": "npc", "id": 3468, "name": "Baroness"}]}))
    (root / "search" / "l.json").write_text(json.dumps({
        "results": [{"type": "npc", "id": 5084, "name": "Longshore"}]}))


class ResolveTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        make_export(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def test_meta(self):
        status, payload, headers = api.resolve(self.root, "/api/world/meta")
        self.assertEqual(status, 200)
        self.assertEqual(payload["counts"]["npc"], 2)
        self.assertIn("ETag", headers)

    def test_entity(self):
        status, payload, _ = api.resolve(self.root, "/api/world/npc/3467")
        self.assertEqual(status, 200)
        self.assertEqual(payload["name"], "Baron Longshore")

    def test_missing_entity(self):
        status, payload, _ = api.resolve(self.root, "/api/world/npc/1")
        self.assertEqual(status, 404)
        self.assertEqual(payload["error"], "not_found")

    def test_invalid_id(self):
        status, _, _ = api.resolve(self.root, "/api/world/npc/abc")
        self.assertEqual(status, 400)

    def test_unknown_type_and_path(self):
        self.assertEqual(api.resolve(self.root, "/api/world/spell/1")[0], 404)
        self.assertEqual(api.resolve(self.root, "/nope")[0], 404)

    def test_search_prefix_and_paging(self):
        status, payload, _ = api.resolve(self.root, "/api/world/search?q=baron&limit=1")
        self.assertEqual(status, 200)
        self.assertEqual(len(payload["results"]), 1)
        self.assertEqual(payload["next"], "1")
        status, payload, _ = api.resolve(self.root, "/api/world/search?q=baron&limit=1&cursor=1")
        self.assertEqual(payload["results"][0]["name"], "Baroness")

    def test_search_without_query(self):
        status, payload, _ = api.resolve(self.root, "/api/world/search")
        self.assertEqual(status, 200)
        self.assertEqual(payload["results"], [])

    def test_search_is_substring_across_buckets(self):
        status, payload, _ = api.resolve(self.root, "/api/world/search?q=shore")
        self.assertEqual(status, 200)
        names = [row["name"] for row in payload["results"]]
        self.assertEqual(names, ["Baron Longshore", "Longshore"])

    def test_invalid_limit(self):
        self.assertEqual(api.resolve(self.root, "/api/world/search?q=a&limit=nope")[0], 400)

    def test_spawn_state_is_deferred(self):
        status, payload, _ = api.resolve(self.root, "/api/world/spawn-state?map=0&entry=1")
        self.assertEqual(status, 501)
        self.assertEqual(payload["error"], "spawn_state_unavailable")

    def test_missing_meta_is_a_startup_error(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(api.ApiError):
                api.load_meta(Path(directory))

    def test_meta_without_counts_is_a_startup_error(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "meta.json").write_text(
                json.dumps({"schemaVersion": 1, "generatedAt": "2026-01-01T00:00:00Z"}))
            with self.assertRaises(api.ApiError):
                api.load_meta(root)


if __name__ == "__main__":
    unittest.main()
