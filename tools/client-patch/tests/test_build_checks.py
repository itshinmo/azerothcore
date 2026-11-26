"""Regression tests for build --check drift detection."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ITEM_BUILD = ROOT / "data" / "client-patches" / "item-data" / "build.py"
MAP_BUILD = ROOT / "data" / "client-patches" / "map-pins" / "build.py"
ITEMS = ROOT / "data" / "client-patches" / "item-data" / "items.json"


class BuildCheckTests(unittest.TestCase):
    def test_stale_items_json_fails_check(self):
        with tempfile.TemporaryDirectory() as folder:
            rows = json.loads(ITEMS.read_text(encoding="utf-8"))
            stale = Path(folder) / "items.json"
            stale.write_text(json.dumps(rows, indent=4) + "\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ITEM_BUILD), "--check", "--items", str(stale)],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("items.json sha256", result.stderr)

    def test_edited_addon_source_fails_source_check(self):
        spec = importlib.util.spec_from_file_location("map_patch_build", MAP_BUILD)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            addon = root / module.ADDON_SOURCE_PREFIX
            addon.mkdir(parents=True)
            source = addon / "WorldMapPins.lua"
            source.write_text("-- edited\n", encoding="utf-8")
            canary = root / module.CANARY_SOURCE
            canary.parent.mkdir(parents=True, exist_ok=True)
            canary.write_text("-- canary\n", encoding="utf-8")
            expected = {
                "sources": [
                    {
                        "source": module.ADDON_SOURCE_PREFIX + "WorldMapPins.lua",
                        "sha256": "0" * 64,
                    }
                ],
                "load_order": {"canary_block_sha256": "0" * 64},
            }
            errors = module.source_errors(expected, root)
            self.assertTrue(any("addon source changed" in error for error in errors))
            self.assertTrue(any("canary source changed" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
