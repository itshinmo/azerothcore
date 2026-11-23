"""Tests for the world-treasure items.json generator/validator."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "data" / "client-patches" / "item-data"))

import generate_items  # noqa: E402

ITEMS = ROOT / "data" / "client-patches" / "item-data" / "items.json"


class GenerateItemsTests(unittest.TestCase):
    def test_sources_match_committed_items(self):
        rows = generate_items.validate_items(ITEMS)
        self.assertEqual(len(rows), 20)
        self.assertEqual(rows[901003]["name"], "Auberdine Tidecaller's Charm")

    def test_each_mirrored_field_must_match(self):
        base = json.loads(ITEMS.read_text(encoding="utf-8"))
        for field, value in (
            ("class", 99),
            ("subclass", 99),
            ("display_info_id", 1),
            ("inventory_type", 99),
            ("sheathe_type", 99),
        ):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as folder:
                rows = json.loads(json.dumps(base))
                rows[0][field] = value
                broken = Path(folder) / "items.json"
                broken.write_text(json.dumps(rows), encoding="utf-8")
                with self.assertRaises(generate_items.ItemsSourceError):
                    generate_items.validate_items(broken)

    def test_csv_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            csv_path = Path(folder) / "batch_01.csv"
            lines = generate_items.DEFAULT_BATCH_CSV.read_text(encoding="utf-8").splitlines()
            lines[1] = lines[1].replace(",54808,", ",1,", 1)
            csv_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            with self.assertRaises(generate_items.ItemsSourceError):
                generate_items.expected_items(batch_csv=csv_path)


if __name__ == "__main__":
    unittest.main()
