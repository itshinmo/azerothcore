"""Tests for tools/icon-browser/gen_icon_list.py.

Run from the repository root::

    python3 -m unittest discover -s tools/icon-browser/tests -v

The parser, merge, render, and staleness checks are pure; no MPQ is opened.
"""

from __future__ import annotations

import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import gen_icon_list  # noqa: E402

STOCK = "patch-enUS.MPQ"
REFORGED = "patch-I.MPQ"


def archive(name: str, *entries: str) -> tuple[str, list[str]]:
    return name, list(entries)


class IconNameTests(unittest.TestCase):
    def test_plain_icon(self):
        self.assertEqual(gen_icon_list.icon_name("Interface\\Icons\\INV_Misc_Anchor.blp"), "INV_Misc_Anchor")

    def test_extension_and_prefix_are_case_insensitive(self):
        self.assertEqual(gen_icon_list.icon_name("interface\\ICONS\\INV_Helmet_93.BLP"), "INV_Helmet_93")

    def test_tga_counts_as_icon_texture(self):
        self.assertEqual(gen_icon_list.icon_name("Interface\\Icons\\Ability_Druid_Mangle.tga"), "Ability_Druid_Mangle")

    def test_other_folders_are_ignored(self):
        for entry in (
            "Interface\\Icon\\INV_Misc_Anchor.blp",
            "Interface\\Icons2\\INV_Misc_Anchor.blp",
            "Spells\\INV_Misc_Anchor.blp",
            "Interface\\Icons\\",
        ):
            with self.subTest(entry=entry):
                self.assertIsNone(gen_icon_list.icon_name(entry))

    def test_forward_slash_entry_is_read(self):
        # SFileFindPath leaves the separator as stored; some archives use "/".
        self.assertEqual(gen_icon_list.icon_name("Interface/Icons/INV_Misc_Anchor.blp"), "INV_Misc_Anchor")

    def test_nested_icon_paths_are_ignored(self):
        self.assertIsNone(gen_icon_list.icon_name("Interface\\Icons\\Old\\INV_Misc_Anchor.blp"))

    def test_non_blp_files_are_ignored(self):
        self.assertIsNone(gen_icon_list.icon_name("Interface\\Icons\\INV_Misc_Anchor.txt"))


class MergeTests(unittest.TestCase):
    def test_stock_archive_tags_stock(self):
        icons = gen_icon_list.merge_icons([archive(STOCK, "Interface\\Icons\\INV_Misc_Anchor.blp")])
        self.assertEqual(icons["inv_misc_anchor"], ("INV_Misc_Anchor", "stock"))

    def test_reforged_archive_tags_reforged(self):
        icons = gen_icon_list.merge_icons([archive(REFORGED, "Interface\\Icons\\INV_BlizzardPhoenixMount.blp")])
        self.assertEqual(icons["inv_blizzardphoenixmount"], ("INV_BlizzardPhoenixMount", "reforged"))

    def test_stock_wins_over_reforged_in_either_order(self):
        entry = "Interface\\Icons\\INV_Misc_Anchor.blp"
        for order in ([archive(STOCK, entry), archive(REFORGED, entry)],
                      [archive(REFORGED, entry), archive(STOCK, entry)]):
            with self.subTest(order=[name for name, _ in order]):
                icons = gen_icon_list.merge_icons(order)
                self.assertEqual(icons["inv_misc_anchor"][1], "stock")
                self.assertEqual(len(icons), 1)

    def test_deduplicates_case_insensitively(self):
        icons = gen_icon_list.merge_icons([
            archive(STOCK, "Interface\\Icons\\INV_Misc_Anchor.blp"),
            archive(REFORGED, "Interface\\Icons\\inv_misc_anchor.blp"),
        ])
        self.assertEqual(len(icons), 1)
        self.assertEqual(icons["inv_misc_anchor"], ("INV_Misc_Anchor", "stock"))

    def test_stock_name_casing_wins_when_both_are_stock(self):
        icons = gen_icon_list.merge_icons([
            archive(STOCK, "Interface\\Icons\\INV_MISC_ANCHOR.blp"),
            archive("patch-2.MPQ", "Interface\\Icons\\INV_Misc_Anchor.blp"),
        ])
        self.assertEqual(icons["inv_misc_anchor"], ("INV_MISC_ANCHOR", "stock"))

    def test_reforged_marker_is_only_on_reforged_rows(self):
        icons = gen_icon_list.merge_icons([
            archive(STOCK, "Interface\\Icons\\INV_Misc_Anchor.blp"),
            archive(REFORGED, "Interface\\Icons\\Achievement_Level_90.blp"),
        ])
        text = gen_icon_list.render(icons)
        self.assertIn('"INV_Misc_Anchor",', text)
        self.assertIn('"Achievement_Level_90#",', text)
        self.assertNotIn('"INV_Misc_Anchor#"', text)

    def test_no_icons_yields_empty_table(self):
        self.assertTrue(gen_icon_list.render({}).endswith("IconBrowserIcons = {\n}\n"))

    def test_stock_name_with_marker_suffix_is_rejected(self):
        with self.assertRaises(gen_icon_list.IconListError):
            gen_icon_list.merge_icons([archive(STOCK, "Interface\\Icons\\Bad#.blp")])


class RenderTests(unittest.TestCase):
    ICONS = {
        "inv_misc_anchor": ("INV_Misc_Anchor", "stock"),
        "achievement_level_90": ("Achievement_Level_90", "reforged"),
    }

    def test_sorted_and_deterministic(self):
        first = gen_icon_list.render(self.ICONS)
        second = gen_icon_list.render(dict(reversed(list(self.ICONS.items()))))
        self.assertEqual(first, second)
        self.assertLess(first.index("Achievement_Level_90"), first.index("INV_Misc_Anchor"))

    def test_one_entry_per_line(self):
        lines = gen_icon_list.render(self.ICONS).splitlines()
        entries = [line for line in lines if line.endswith(",")]
        self.assertEqual(entries, ['"Achievement_Level_90#",', '"INV_Misc_Anchor",'])

    def test_header_states_the_marker_rule(self):
        text = gen_icon_list.render(self.ICONS)
        self.assertIn('trailing "#" marks a Reforged icon', text)
        self.assertIn("IconBrowserIcons = {", text)

    def test_counts(self):
        self.assertEqual(gen_icon_list.counts(self.ICONS), (2, 1, 1))
        self.assertEqual(gen_icon_list.counts({}), (0, 0, 0))

    def test_lua_string_escapes(self):
        self.assertEqual(gen_icon_list.lua_string('A"B'), '"A\\"B"')
        self.assertEqual(gen_icon_list.lua_string("A\\B"), '"A\\\\B"')


class StalenessTests(unittest.TestCase):
    def test_missing_file_is_stale(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "IconBrowserIcons.lua"
            self.assertTrue(gen_icon_list.is_stale(path, "x\n"))
            path.write_text("x\n", encoding="utf-8")
            self.assertFalse(gen_icon_list.is_stale(path, "x\n"))
            path.write_text("y\n", encoding="utf-8")
            self.assertTrue(gen_icon_list.is_stale(path, "x\n"))

    def test_committed_file_is_the_shipped_list(self):
        # Assert on the committed file's own content, not on itself as its expected value:
        # comparing the file to a string read from that same file can never fail.
        committed = Path(__file__).resolve().parents[1] / "IconBrowserIcons.lua"
        if not committed.is_file():
            self.skipTest("IconBrowserIcons.lua is not generated yet")
        text = committed.read_text(encoding="utf-8")
        lines = [line for line in text.splitlines() if line.startswith('"') and line.endswith(',')]
        self.assertGreater(len(lines), 30000, "the shipped list lost entries")
        self.assertTrue(lines[0].endswith(('",', '"#,')), lines[0])
        # The data file must be byte-identical to what render() produces for its own contents,
        # so parse it back and re-render.
        icons = {}
        for line in lines:
            raw = line.strip().rstrip(",")
            entry = raw[1:-1]
            reforged = entry.endswith("#")
            name = entry[:-1] if reforged else entry
            icons[name.lower()] = (name, "reforged" if reforged else "stock")
        self.assertEqual(gen_icon_list.render(icons), text)

    def test_check_mode_fails_on_stale_output(self):
        icons = {"inv_axe_01": ("INV_Axe_01", "stock")}
        expected = gen_icon_list.render(icons)
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder) / "icons.lua"
            out.write_text(expected, encoding="utf-8")
            with unittest.mock.patch.object(gen_icon_list, "load_client_icons", return_value=icons):
                self.assertEqual(gen_icon_list.main(["--check", "--out", str(out)]), 0)
                out.write_text("stale\n", encoding="utf-8")
                self.assertEqual(gen_icon_list.main(["--check", "--out", str(out)]), 1)


class UnreadableArchiveTests(unittest.TestCase):
    def test_an_unreadable_archive_is_fatal_not_skipped(self):
        # Skipping a stock archive silently drops its icons, or flips shared ones to Reforged,
        # and --check then reports the lossy result as up to date.
        with tempfile.TemporaryDirectory() as folder:
            data = Path(folder) / "Data"
            data.mkdir()
            (data / "patch-3.MPQ").write_bytes(b"not an mpq")
            with unittest.mock.patch.object(
                gen_icon_list, "archive_chain", return_value=[data / "patch-3.MPQ"]
            ):
                with self.assertRaises(gen_icon_list.IconListError) as caught:
                    gen_icon_list.load_client_icons(str(data))
            self.assertIn("cannot read", str(caught.exception))

    def test_zero_icons_is_fatal(self):
        with tempfile.TemporaryDirectory() as folder:
            data = Path(folder) / "Data"
            data.mkdir()
            empty = data / "patch-3.MPQ"
            empty.write_bytes(b"x")

            class FakeArchive:
                def __init__(self, path):
                    pass

                def __enter__(self):
                    return self

                def __exit__(self, *args):
                    return False

                def list_files(self):
                    return []

            with unittest.mock.patch.object(
                gen_icon_list, "archive_chain", return_value=[empty]
            ), unittest.mock.patch.object(gen_icon_list, "Archive", FakeArchive):
                with self.assertRaises(gen_icon_list.IconListError) as caught:
                    gen_icon_list.load_client_icons(str(data))
            self.assertIn("no Interface", str(caught.exception))


class MissingClientTests(unittest.TestCase):
    def test_missing_data_dir_fails_cleanly(self):
        with tempfile.TemporaryDirectory() as folder:
            client = Path(folder) / "no-client"
            client.mkdir()
            with self.assertRaises(gen_icon_list.IconListError) as caught:
                gen_icon_list.load_client_icons(str(client))
            self.assertIn("Data directory not found", str(caught.exception))

    def test_empty_data_dir_fails_cleanly(self):
        with tempfile.TemporaryDirectory() as folder:
            client = Path(folder) / "client"
            (client / "Data").mkdir(parents=True)
            with self.assertRaises(gen_icon_list.IconListError) as caught:
                gen_icon_list.load_client_icons(str(client))
            self.assertIn("no MPQ archives", str(caught.exception))

    def test_main_reports_clean_error(self):
        with tempfile.TemporaryDirectory() as folder:
            code = gen_icon_list.main(["--client", str(Path(folder) / "absent"), "--out", str(Path(folder) / "o.lua")])
            self.assertEqual(code, 2)
            self.assertFalse((Path(folder) / "o.lua").exists())


if __name__ == "__main__":
    unittest.main()
