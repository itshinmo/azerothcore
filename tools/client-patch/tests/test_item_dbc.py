"""Unit tests for the Item.dbc editor and patch-X builder.

Run from the repository root::

    python3 -m unittest discover -s tools/client-patch/tests -v

MPQ build tests skip when StormLib is absent. Pure DBC tests always run.
"""

from __future__ import annotations

import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import item_dbc  # noqa: E402
import mpq  # noqa: E402

FIXTURE_ITEM = {
    "id": 901001,
    "name": "Fixture Chip",
    "class": 4,
    "subclass": 0,
    "sound_override_subclass": -1,
    "material": 7,
    "display_info_id": 54808,
    "inventory_type": 23,
    "sheathe_type": 0,
}


def row(item_id: int, display: int = 1000) -> item_dbc.ItemRow:
    return item_dbc.ItemRow(
        id=item_id,
        item_class=4,
        subclass=0,
        sound_override_subclass=-1,
        material=7,
        display_info_id=display,
        inventory_type=23,
        sheathe_type=0,
    )


def dbc_bytes(rows: list[item_dbc.ItemRow], strings: bytes = b"\0") -> bytes:
    data = bytearray(struct.pack("<4s4I", b"WDBC", len(rows), 8, 32, len(strings)))
    for item in rows:
        data += struct.pack("<8I", *item.to_values())
    data += strings
    return bytes(data)


class ItemDbcTests(unittest.TestCase):
    def test_round_trip_preserves_signed_sound_override(self):
        dbc = item_dbc.ItemDbc.from_bytes(dbc_bytes([row(1), row(2)]))
        self.assertEqual(dbc.rows[1].sound_override_subclass, -1)
        self.assertEqual(dbc.to_bytes(), dbc_bytes([row(1), row(2)]))
        self.assertTrue(dbc.summary()["sorted"])

    def test_upsert_adds_and_updates_sorted(self):
        dbc = item_dbc.ItemDbc.from_bytes(dbc_bytes([row(1), row(3)]))
        added, updated = dbc.upsert([row(2), row(3, display=2000), row(4)])
        self.assertEqual(added, [2, 4])
        self.assertEqual(updated, [3])
        reparsed = item_dbc.ItemDbc.from_bytes(dbc.to_bytes())
        self.assertEqual([item.id for item in sorted(reparsed.rows.values(), key=lambda r: r.id)], [1, 2, 3, 4])
        self.assertEqual(reparsed.rows[3].display_info_id, 2000)

    def test_rejects_wrong_magic(self):
        data = bytearray(dbc_bytes([row(1)]))
        data[0:4] = b"NOPE"
        with self.assertRaises(item_dbc.ItemDbcError):
            item_dbc.ItemDbc.from_bytes(bytes(data))

    def test_rejects_wrong_field_count_or_row_size(self):
        data = dbc_bytes([row(1)])
        with self.assertRaises(item_dbc.ItemDbcError):
            item_dbc.ItemDbc.from_bytes(struct.pack("<4s4I", b"WDBC", 0, 7, 32, 1))
        with self.assertRaises(item_dbc.ItemDbcError):
            item_dbc.ItemDbc.from_bytes(struct.pack("<4s4I", b"WDBC", 0, 8, 28, 1))

    def test_rejects_truncated_body(self):
        data = dbc_bytes([row(1)])
        with self.assertRaises(item_dbc.ItemDbcError):
            item_dbc.ItemDbc.from_bytes(data[:-2])

    def test_rejects_duplicate_id(self):
        with self.assertRaises(item_dbc.ItemDbcError):
            item_dbc.ItemDbc.from_bytes(dbc_bytes([row(1), row(1)]))

    def test_missing_item_display_info_fails(self):
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / "Data").mkdir()
            with self.assertRaises(item_dbc.ItemDbcError):
                item_dbc.item_display_ids(folder)

    def test_item_display_ids_header_is_length_checked(self):
        with self.assertRaises(item_dbc.ItemDbcError):
            item_dbc.parse_item_display_ids(b"\0" * 8)
        with self.assertRaises(item_dbc.ItemDbcError):
            item_dbc.parse_item_display_ids(
                struct.pack("<4s4I", b"WDBC", 1, 25, 4, 0) + b"\0\0"
            )


@unittest.skipUnless(mpq.stormlib_available(), f"StormLib not available at {mpq.stormlib_path()}")
class ItemPatchTests(unittest.TestCase):
    def test_build_patch_contains_only_item_dbc(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "Item.source.dbc"
            source.write_bytes(dbc_bytes([row(1)]))
            items = root / "items.json"
            items.write_text(json.dumps([FIXTURE_ITEM]), encoding="utf-8")
            out = root / "dist" / "patch-X.MPQ"
            manifest_path = root / "manifest.json"
            manifest = item_dbc.build_patch(
                source,
                items,
                out,
                manifest_path,
                source_label="fixture/Item.dbc",
                displays={FIXTURE_ITEM["display_info_id"]},
            )
            self.assertEqual(manifest["dbc_files"], 1)
            self.assertEqual(manifest["dbc"][0]["added_ids"], [FIXTURE_ITEM["id"]])
            self.assertEqual(manifest["dbc"][0]["rows_before"], 1)
            self.assertEqual(manifest["dbc"][0]["rows_after"], 2)
            self.assertEqual(
                manifest["load_order"]["only_item_dbc_carrier"], "patch-X.MPQ"
            )
            with mpq.Archive(out) as archive:
                names = {
                    entry.name.lower()
                    for entry in archive.list_files(include_internal=True)
                }
                self.assertEqual(
                    names,
                    {
                        "dbfilesclient\\item.dbc",
                        "(listfile)",
                        "(attributes)",
                    },
                )
                dbc = item_dbc.ItemDbc.from_bytes(archive.read_file(item_dbc.ITEM_DBC_PATH))
                self.assertEqual(sorted(dbc.rows), [1, FIXTURE_ITEM["id"]])
                self.assertEqual(
                    dbc.rows[FIXTURE_ITEM["id"]].display_info_id,
                    FIXTURE_ITEM["display_info_id"],
                )
            self.assertEqual(
                json.loads(manifest_path.read_text(encoding="utf-8"))["sha256"],
                manifest["sha256"],
            )

    def test_server_dbc_records_clean_input(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "Item.source.dbc"
            source.write_bytes(dbc_bytes([row(1)]))
            server = root / "Item.server.dbc"
            server.write_bytes(dbc_bytes([row(1), row(FIXTURE_ITEM["id"], FIXTURE_ITEM["display_info_id"])]))
            items = root / "items.json"
            items.write_text(json.dumps([FIXTURE_ITEM]), encoding="utf-8")
            manifest = item_dbc.build_patch(
                source,
                items,
                root / "dist" / "patch-X.MPQ",
                root / "manifest.json",
                source_label="fixture/Item.dbc",
                displays={FIXTURE_ITEM["display_info_id"]},
                server_dbc=server,
            )
            self.assertEqual(manifest["server_dbc_input"]["server_only_ids"], [])
            self.assertEqual(
                manifest["server_dbc_input"]["sha256"], mpq.sha256_file(server)
            )

    def test_server_dbc_rejects_server_only_ids(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "Item.source.dbc"
            source.write_bytes(dbc_bytes([row(1)]))
            server = root / "Item.server.dbc"
            server.write_bytes(
                dbc_bytes(
                    [
                        row(1),
                        row(FIXTURE_ITEM["id"], FIXTURE_ITEM["display_info_id"]),
                        row(2050641, 1),
                    ]
                )
            )
            items = root / "items.json"
            items.write_text(json.dumps([FIXTURE_ITEM]), encoding="utf-8")
            with self.assertRaisesRegex(item_dbc.ItemDbcError, "2050641"):
                item_dbc.build_patch(
                    source,
                    items,
                    root / "dist" / "patch-X.MPQ",
                    root / "manifest.json",
                    source_label="fixture/Item.dbc",
                    displays={FIXTURE_ITEM["display_info_id"]},
                    server_dbc=server,
                )

    def test_display_check_rejects_missing_display(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "Item.source.dbc"
            source.write_bytes(dbc_bytes([row(1)]))
            items = root / "items.json"
            items.write_text(json.dumps([FIXTURE_ITEM]), encoding="utf-8")
            with self.assertRaises(item_dbc.ItemDbcError):
                item_dbc.build_patch(
                    source,
                    items,
                    root / "patch-X.MPQ",
                    root / "manifest.json",
                    source_label="fixture/Item.dbc",
                    displays=set(),
                )


if __name__ == "__main__":
    unittest.main()
