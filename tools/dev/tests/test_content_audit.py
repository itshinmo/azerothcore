#!/usr/bin/env python3
"""Unit tests for tools/dev/content-audit.py.

Run with: python3 -m unittest discover -s tools/dev/tests -v
"""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "content-audit.py"
SPEC = importlib.util.spec_from_file_location("content_audit", SCRIPT)
assert SPEC and SPEC.loader
audit = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = audit
SPEC.loader.exec_module(audit)


class SmartLimitsTest(unittest.TestCase):
    def test_reads_max_explicit_values(self):
        header = """
        enum SMART_EVENT
        {
            SMART_EVENT_RESPAWN = 0,
            SMART_EVENT_UPDATE_IC = 1, // updates in combat, two params
            SMART_EVENT_CUSTOM = 3,
        };

        enum SMART_ACTION
        {
            SMART_ACTION_NONE = 0,
            SMART_ACTION_TALK = 2,
        };

        enum SMARTAI_TARGETS
        {
            SMART_TARGET_NONE = 0,
            SMART_TARGET_SELF = 1,
        };

        enum SMART_EVENT_PHASE_BITS
        {
            SMART_EVENT_PHASE_1_BIT = 1,
            SMART_EVENT_PHASE_2_BIT = 2,
            SMART_EVENT_PHASE_12_BIT = 2048,
        };

        enum SMART_EVENT_PHASE
        {
            SMART_EVENT_PHASE_1 = 1,
        };
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "SmartScriptMgr.h"
            path.write_text(header, encoding="utf-8")
            limits = audit.smart_limits(path)
        self.assertEqual(limits["event"], 4)
        self.assertEqual(limits["action"], 3)
        self.assertEqual(limits["target"], 2)
        self.assertEqual(limits["phase_mask"], 2051)

    def test_missing_file_is_an_audit_error(self):
        with self.assertRaises(audit.AuditError):
            audit.smart_limits(Path("/nonexistent/SmartScriptMgr.h"))


class CheckC06Test(unittest.TestCase):
    def test_cycle_does_not_stop_other_blocks(self):
        data = {"smart": [
            {"entryorguid": 10, "source_type": 0, "id": 1, "link": 2},
            {"entryorguid": 10, "source_type": 0, "id": 2, "link": 1},
            {"entryorguid": 20, "source_type": 0, "id": 1, "link": 9},
        ]}
        causes = " ".join(finding.cause for finding in audit.check_c06(data))
        self.assertIn("link cycle", causes)
        self.assertIn("missing id 9", causes)


class CheckC05Test(unittest.TestCase):
    def test_flags_type_chance_and_phase(self):
        data = {
            "smart_limits": {"event": 2, "action": 2, "target": 2, "phase_mask": 4095},
            "smart": [{"entryorguid": 5, "source_type": 0, "id": 0, "event": 2,
                       "action": 0, "target": 0, "chance": 101, "phase_mask": 4096}],
        }
        causes = " ".join(finding.cause for finding in audit.check_c05(data))
        self.assertIn("event_type 2 is outside", causes)
        self.assertIn("event_chance 101", causes)
        self.assertIn("event_phase_mask 4096", causes)


class CheckC11Test(unittest.TestCase):
    def test_flags_flags_missing_stock_and_missing_spells(self):
        data = {
            "vendor_flag": {10}, "vendor_rows": set(), "vendor_items": [(11, 999)],
            "trainer_flag": {20}, "creature_trainer": {20: 1}, "trainer_rows": {2},
            "trainer_spells": [(2, 777)], "spell_entries": {1},
            "item_entries": {1},
        }
        findings = audit.check_c11(data)
        by_cause = {finding.cause: finding.severity for finding in findings}
        self.assertEqual(by_cause["vendor flag set but npc_vendor has no rows"], "minor")
        self.assertEqual(by_cause["vendor sells missing item_template entry"], "blocker")
        self.assertEqual(
            by_cause["trainer flag set but no creature_default_trainer or trainer_spell rows"],
            "minor")
        self.assertEqual(by_cause["trainer teaches missing Spell.dbc spell 777"], "major")


class DatabaseNameTest(unittest.TestCase):
    def test_accepts_world_suffix(self):
        audit.ensure_world_database("acore_world")
        audit.ensure_world_database("acore_test_world")

    def test_rejects_other_databases(self):
        for name in ("acore_auth", "acore_characters", "world", ""):
            with self.subTest(name=name), self.assertRaises(audit.AuditError):
                audit.ensure_world_database(name)


class WaiverTest(unittest.TestCase):
    def finding(self, check="C-01", kind="creature", entity=5):
        return audit.Finding(check, "blocker", kind, entity, "loc", "cause")

    def test_matching_waiver_removes_finding(self):
        waiver = {"check": "C-01", "entity_kind": "creature", "entity_id": 5,
                  "reason": "known", "accepted_by": "human"}
        kept, waived, stale = audit.apply_waivers([self.finding()], [waiver])
        self.assertEqual(kept, [])
        self.assertEqual(len(waived), 1)
        self.assertEqual(stale, [])

    def test_unmatched_waiver_is_stale(self):
        waiver = {"check": "C-99", "entity_kind": "item", "entity_id": 1,
                  "reason": "gone"}
        kept, waived, stale = audit.apply_waivers([self.finding()], [waiver])
        self.assertEqual(len(kept), 1)
        self.assertEqual(waived, [])
        self.assertEqual(stale, [waiver])

    def test_malformed_waiver_is_an_error(self):
        with self.assertRaises(audit.AuditError):
            audit.apply_waivers([self.finding()], [{"check": "C-01"}])

    def test_missing_reason_is_an_error(self):
        waiver = {"check": "C-01", "entity_kind": "creature", "entity_id": 5}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "waivers.json"
            path.write_text(json.dumps({"waivers": [waiver]}), encoding="utf-8")
            with self.assertRaises(audit.AuditError):
                audit.load_waivers(path)

    def test_duplicate_waiver_is_an_error(self):
        waiver = {"check": "C-01", "entity_kind": "creature", "entity_id": 5,
                  "reason": "known", "accepted_by": "human"}
        with self.assertRaises(audit.AuditError):
            audit.apply_waivers([self.finding()], [waiver, dict(waiver)])


class CoverageTest(unittest.TestCase):
    def test_bands_count_starters_and_blocked_quests(self):
        quests = [
            {"id": 1, "level": 10, "start_item": 0},
            {"id": 2, "level": 10, "start_item": 0},
            {"id": 3, "level": 30, "start_item": 0},
            {"id": 4, "level": 30, "start_item": 9},
        ]
        data = {
            "quests": quests,
            "starters": {"creature_queststarter": [(100, 1), (100, 2), (100, 3)],
                         "gameobject_queststarter": []},
        }
        findings = [audit.Finding("C-02", "minor", "creature", 7, "quest 2", "x",
                                  quest_id=2)]
        result = audit.coverage(data, findings)
        bands = [row for row in result["bands"] if row["band"] != "overall"]
        low, high = bands
        self.assertEqual((low["quests"], low["covered"]), (2, 1))
        self.assertEqual((high["quests"], high["covered"]), (2, 2))
        self.assertEqual(high["percent"], 100.0)
        self.assertEqual(result["bands"][-1]["band"], "overall")


class ReportTest(unittest.TestCase):
    def test_markdown_counts_and_limit(self):
        result = {
            "generatedAt": "2026-01-01T00:00:00Z",
            "database": "acore_world",
            "sourceVersion": "test",
            "findings": [audit.Finding("C-01", "blocker", "creature", index, "l", "c").as_dict()
                         for index in range(3)],
            "waived": [],
            "staleWaivers": [],
            "coverage": {"bands": [{"band": "1-20", "quests": 1, "covered": 1,
                                    "percent": 100.0}]},
            "warnings": [],
        }
        text = audit.render_markdown(result, 2)
        self.assertIn("3 blocker", text)
        self.assertIn("Showing 2 of 3 findings", text)


class ConfigTest(unittest.TestCase):
    def test_parses_world_dsn_and_data_dir(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "worldserver.conf"
            path.write_text(
                'DataDir = "/data"\n'
                'WorldDatabaseInfo = "127.0.0.1;3306;acore;secret;acore_world"\n',
                encoding="utf-8")
            dsn = audit.parse_world_dsn(path)
            self.assertEqual(dsn["database"], "acore_world")
            self.assertEqual(dsn["user"], "acore")
            self.assertEqual(audit.parse_data_dir(path), Path("/data"))

    def test_missing_world_dsn_is_an_error(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "worldserver.conf"
            path.write_text("DataDir = \"/data\"\n", encoding="utf-8")
            with self.assertRaises(audit.AuditError):
                audit.parse_world_dsn(path)


class DbcTest(unittest.TestCase):
    def test_reads_ids_from_wdbc(self):
        import struct

        records = [(11, 0), (22, 1)]
        record_size = 8
        payload = b"".join(struct.pack("<II", *record) for record in records)
        header = struct.pack("<4sIIII", b"WDBC", len(records), 2, record_size, 0)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Test.dbc"
            path.write_bytes(header + payload)
            self.assertEqual(audit.dbc_ids(path), {11, 22})

    def test_rejects_wrong_magic(self):
        import struct

        header = struct.pack("<4sIIII", b"NOPE", 1, 1, 4, 0)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Bad.dbc"
            path.write_bytes(header)
            with self.assertRaises(audit.AuditError):
                audit.dbc_ids(path)


class WaiverFileTest(unittest.TestCase):
    def test_missing_file_means_no_waivers(self):
        self.assertEqual(audit.load_waivers(Path("/nonexistent/waivers.json")), [])

    def test_bad_json_is_an_error(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "waivers.json"
            path.write_text(json.dumps({"waivers": "nope"}), encoding="utf-8")
            with self.assertRaises(audit.AuditError):
                audit.load_waivers(path)


if __name__ == "__main__":
    unittest.main()
