"""Tests for the patch-Z Cooldown.lua nil guard."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "client-patch"))
sys.path.insert(0, str(ROOT / "data" / "client-patches" / "map-poi"))

import build  # noqa: E402

STOCK = b"""
function CooldownFrame_SetTimer(self, start, duration, enable)
\tif ( start > 0 and duration > 0 and enable > 0) then
\t\tself:SetCooldown(start, duration);
\t\tself:Show();
\telse
\t\tself:Hide();
\tend
end
"""


class CooldownPatchTests(unittest.TestCase):
    def test_adds_nil_guards(self):
        output = build.patch_cooldown(STOCK)
        self.assertIn(b"start and duration and enable and start > 0", output)
        self.assertIn(b"function CooldownFrame_SetTimer(self, start, duration, enable)", output)

    def test_keeps_existing_behaviour(self):
        output = build.patch_cooldown(STOCK)
        self.assertIn(b"self:SetCooldown(start, duration);", output)
        self.assertIn(b"self:Show();", output)
        self.assertIn(b"self:Hide();", output)

    def test_marks_the_file_as_patched(self):
        output = build.patch_cooldown(STOCK)
        self.assertTrue(output.startswith(build.COOLDOWN_MARKER))

    def test_rejects_an_already_patched_file(self):
        output = build.patch_cooldown(STOCK)
        with self.assertRaises(SystemExit):
            build.patch_cooldown(output)

    def test_rejects_a_different_body(self):
        with self.assertRaises(SystemExit):
            build.patch_cooldown(b"function something_else() end\n")

    def test_rejects_two_matching_conditions(self):
        with self.assertRaises(SystemExit):
            build.patch_cooldown(STOCK + STOCK)

    def test_cooldown_source_skips_patch_z(self):
        lower = Path("/tmp/locale-enUS.MPQ")
        patchz = Path("/tmp/patch-Z.MPQ")
        result = build.mpq.WhichResult("Cooldown.lua", patchz, (lower, patchz), ())
        with mock.patch.object(build.mpq, "find_highest", return_value=result):
            source, _ = build.cooldown_source(Path("/tmp"))
        self.assertEqual(source, lower)

    def test_cooldown_source_fails_when_only_patch_z_has_it(self):
        patchz = Path("/tmp/patch-Z.MPQ")
        result = build.mpq.WhichResult("Cooldown.lua", patchz, (patchz,), ())
        with mock.patch.object(build.mpq, "find_highest", return_value=result):
            with self.assertRaises(SystemExit):
                build.cooldown_source(Path("/tmp"))


if __name__ == "__main__":
    unittest.main()
