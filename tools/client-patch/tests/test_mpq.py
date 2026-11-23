"""Unit tests for the client-patch MPQ wrapper.

Run from the repository root::

    python3 -m unittest discover -s tools/client-patch/tests -v

Archive tests skip when StormLib is not installed. Path-safety tests always run.
"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mpq  # noqa: E402

STORM = mpq.stormlib_available()
SKIP_STORM = unittest.skipUnless(STORM, f"StormLib not available at {mpq.stormlib_path()}")


class PathTests(unittest.TestCase):
    def test_normalize_accepts_client_paths(self):
        self.assertEqual(
            mpq.normalize_archive_path("Interface\\FrameXML\\WorldMapFrame.lua"),
            "Interface\\FrameXML\\WorldMapFrame.lua",
        )
        self.assertEqual(
            mpq.normalize_archive_path("Interface//AddOns/./ServerMapPOI/"),
            "Interface\\AddOns\\ServerMapPOI",
        )

    def test_normalize_rejects_unsafe_paths(self):
        for value in ("", "..", "../evil.txt", "Interface\\..\\evil.txt", "/etc/passwd", "C:\\x"):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    mpq.normalize_archive_path(value)

    def test_safe_destination_stays_below_root(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            target = mpq.safe_destination(root, "Interface\\AddOns\\ServerMapPOI\\A.lua")
            self.assertEqual(
                target, (root / "Interface" / "AddOns" / "ServerMapPOI" / "A.lua").resolve()
            )
            with self.assertRaises(ValueError):
                mpq.safe_destination(root, "..\\escape.txt")

    def test_safe_destination_rejects_symlink_escape(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / "root"
            outside = Path(folder) / "outside"
            root.mkdir()
            outside.mkdir()
            (root / "Interface").symlink_to(outside, target_is_directory=True)
            with self.assertRaises(ValueError):
                mpq.safe_destination(root, "Interface\\escape.txt")

    def test_sha256_known_value(self):
        self.assertEqual(
            mpq.sha256_bytes(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        )

    def test_archive_chain_english_order(self):
        with tempfile.TemporaryDirectory() as folder:
            data = Path(folder)
            (data / "enUS").mkdir()
            names = [
                data / "common.MPQ",
                data / "patch.MPQ",
                data / "patch-3.MPQ",
                data / "patch-A.MPQ",
                data / "patch-Z.MPQ",
                data / "enUS" / "locale-enUS.MPQ",
                data / "enUS" / "patch-enUS-3.MPQ",
                data / "enUS" / "patch-enUS-Z.MPQ",
            ]
            for name in names:
                name.write_bytes(b"x")
            chain = mpq.archive_chain(data, order="english")
            expected = [
                data / "enUS" / "locale-enUS.MPQ",
                data / "enUS" / "patch-enUS-3.MPQ",
                data / "enUS" / "patch-enUS-Z.MPQ",
                data / "common.MPQ",
                data / "patch.MPQ",
                data / "patch-3.MPQ",
                data / "patch-A.MPQ",
                data / "patch-Z.MPQ",
            ]
            self.assertEqual(chain, expected)

    def test_archive_chain_localized_order(self):
        with tempfile.TemporaryDirectory() as folder:
            data = Path(folder)
            (data / "enUS").mkdir()
            (data / "common.MPQ").write_bytes(b"x")
            (data / "patch-Z.MPQ").write_bytes(b"x")
            (data / "enUS" / "patch-enUS-Z.MPQ").write_bytes(b"x")
            chain = mpq.archive_chain(data, order="localized")
            self.assertEqual(
                chain,
                [
                    data / "common.MPQ",
                    data / "patch-Z.MPQ",
                    data / "enUS" / "patch-enUS-Z.MPQ",
                ],
            )


@SKIP_STORM
class ArchiveTests(unittest.TestCase):
    def make_archive(
        self, folder: Path, files: dict[str, bytes], filename: str = "test.MPQ"
    ) -> Path:
        path = folder / filename
        with mpq.Archive.create(path, max_files=max(16, len(files) * 2)) as archive:
            for name, data in files.items():
                source = folder / ("src-" + Path(name.replace("\\", "/")).name)
                source.write_bytes(data)
                archive.add_file(source, name)
        return path

    def test_pack_read_round_trip(self):
        files = {
            "Interface\\AddOns\\ServerMapPOI\\ServerMapPOI.toc": b"## Interface: 30300\n",
            "Interface\\FrameXML\\WorldMapFrame.lua": b"-- canary\n",
            "Interface\\AddOns\\ServerMapPOI\\Empty.lua": b"",
            "Interface\\Icons\\blob.bin": bytes(range(256)) * 501,
        }
        with tempfile.TemporaryDirectory() as folder:
            folder_path = Path(folder)
            archive_path = self.make_archive(folder_path, files)
            with mpq.Archive(archive_path) as archive:
                info = archive.inspect()
                self.assertEqual(info["format"], "MPQ v1")
                self.assertTrue(info["listfile"])
                self.assertTrue(info["attributes"])
                self.assertEqual(info["files"], len(files))
                listed = {entry.name for entry in archive.list_files()}
                self.assertEqual(listed, set(files))
                for name, data in files.items():
                    self.assertEqual(archive.read_file(name), data)
                    self.assertEqual(archive.sha256(name), mpq.sha256_bytes(data))
                    result = archive.verify_file(name)
                    self.assertTrue(result.ok, f"{name}: flags {result.flags:#x}")
                self.assertIsNotNone(archive.attributes())
                self.assertIn(
                    "Interface\\AddOns\\ServerMapPOI\\ServerMapPOI.toc",
                    archive.listfile(),
                )

    def test_extract_all_is_safe(self):
        files = {
            "Interface\\AddOns\\ServerMapPOI\\A.lua": b"A",
            "Interface\\AddOns\\ServerMapPOI\\nested\\B.lua": b"B",
        }
        with tempfile.TemporaryDirectory() as folder:
            folder_path = Path(folder)
            archive_path = self.make_archive(folder_path, files)
            out = folder_path / "out"
            with mpq.Archive(archive_path) as archive:
                targets = archive.extract_all(out)
                self.assertEqual(len(targets), 2)
                for target in targets:
                    self.assertTrue(target.is_file())
                    self.assertTrue(target.resolve().is_relative_to(out.resolve()))
                self.assertEqual((out / "Interface" / "AddOns" / "ServerMapPOI" / "A.lua").read_bytes(), b"A")

    def test_which_prefers_base_alphabetic_patch(self):
        with tempfile.TemporaryDirectory() as folder:
            data = Path(folder) / "Data"
            (data / "enUS").mkdir(parents=True)
            path = "Interface\\FrameXML\\WorldMapFrame.lua"
            for target in (data / "enUS" / "patch-enUS-3.MPQ", data / "patch-A.MPQ", data / "patch-Z.MPQ"):
                self.make_archive(target.parent, {path: str(target).encode()}, target.name)
            result = mpq.find_highest(data, path, order="english")
            self.assertEqual(result.winner, data / "patch-Z.MPQ")
            self.assertEqual(
                result.sources,
                (data / "enUS" / "patch-enUS-3.MPQ", data / "patch-A.MPQ", data / "patch-Z.MPQ"),
            )

    def test_which_localized_prefers_locale_patch(self):
        with tempfile.TemporaryDirectory() as folder:
            data = Path(folder) / "Data"
            (data / "enUS").mkdir(parents=True)
            path = "Interface\\FrameXML\\WorldMapFrame.lua"
            for target in (data / "patch-Z.MPQ", data / "enUS" / "patch-enUS-Z.MPQ"):
                self.make_archive(target.parent, {path: b"x"}, target.name)
            result = mpq.find_highest(data, path, order="localized")
            self.assertEqual(result.winner, data / "enUS" / "patch-enUS-Z.MPQ")


if __name__ == "__main__":
    unittest.main()
