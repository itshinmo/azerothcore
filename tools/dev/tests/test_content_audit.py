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
            SMART_EVENT_PHASE_COUNT = 12,
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
        self.assertEqual(limits["phase_max"], 12)

    def test_missing_file_is_an_audit_error(self):
        with self.assertRaises(audit.AuditError):
            audit.smart_limits(Path("/nonexistent/SmartScriptMgr.h"))


def smart_row(entry, row_id, mask=0, action=0, params=(), source_type=0, **extra):
    """A smart_scripts row shaped like the extractor output."""
    row = {"entryorguid": entry, "source_type": source_type, "id": row_id, "link": 0,
           "phase_mask": mask, "action": action, "target": 0, "target_param1": 0}
    for index in range(1, 7):
        row[f"param{index}"] = params[index - 1] if index <= len(params) else 0
    row.update(extra)
    return row


class CheckC06Test(unittest.TestCase):
    def test_cycle_does_not_stop_other_blocks(self):
        data = {"smart": [
            smart_row(10, 1, link=2),
            smart_row(10, 2, link=1),
            smart_row(20, 1, link=9),
        ]}
        causes = " ".join(finding.cause for finding in audit.check_c06(data))
        self.assertIn("link cycle", causes)
        self.assertIn("missing id 9", causes)

    def test_set_event_phase_unlocks_a_phase(self):
        rows = [smart_row(1, 0, action=22, params=(2,)),
                smart_row(1, 1, mask=0x2)]
        self.assertEqual(audit.reachable_phases(rows), {0, 2})
        self.assertEqual(audit.check_c06({"smart": rows}), [])

    def test_inc_event_phase_chain_unlocks_later_phases(self):
        rows = [smart_row(1, 0, action=22, params=(1,)),
                smart_row(1, 1, mask=0x1, action=23, params=(1, 0)),
                smart_row(1, 2, mask=0x2, action=23, params=(1, 0)),
                smart_row(1, 3, mask=0x4)]
        self.assertEqual(audit.reachable_phases(rows), {0, 1, 2, 3})
        self.assertEqual(audit.check_c06({"smart": rows}), [])

    def test_inc_event_phase_decrements(self):
        rows = [smart_row(1, 0, action=22, params=(5,)),
                smart_row(1, 1, mask=0x10, action=23, params=(0, 2)),
                smart_row(1, 2, mask=0x8, action=23, params=(0, 5))]
        self.assertEqual(audit.reachable_phases(rows), {0, 3, 5})

    def test_random_phase_actions_unlock_every_option(self):
        rows = [smart_row(1, 0, action=30, params=(3, 5, 0, 0, 0, 0)),
                smart_row(1, 1, action=31, params=(7, 9)),
                smart_row(1, 2, mask=0x80)]
        self.assertEqual(audit.reachable_phases(rows), {0, 3, 5, 7, 8, 9})
        self.assertEqual(audit.check_c06({"smart": rows}), [])

    def test_unreachable_mask_is_reported_once_per_row(self):
        rows = [smart_row(1, 0, mask=0x4), smart_row(1, 1, mask=0x8)]
        findings = audit.check_c06({"smart": rows})
        self.assertEqual(len(findings), 2)
        causes = " ".join(finding.cause for finding in findings)
        self.assertIn("phase mask 0x4 is not reachable", causes)
        self.assertIn("phase mask 0x8 is not reachable", causes)
        self.assertIn("reachable phases: 0", causes)

    def test_action_in_unreachable_row_does_not_unlock(self):
        rows = [smart_row(1, 0, mask=0x2, action=22, params=(3,)),
                smart_row(1, 1, mask=0x4)]
        self.assertEqual(audit.reachable_phases(rows), {0})
        self.assertEqual(len(audit.check_c06({"smart": rows})), 2)

    def test_mask_zero_always_runs(self):
        rows = [smart_row(1, 0), smart_row(1, 1, action=22, params=(1,)),
                smart_row(1, 2, mask=0x1)]
        self.assertEqual(audit.reachable_phases(rows), {0, 1})
        self.assertEqual(audit.check_c06({"smart": rows}), [])

    def test_phase_zero_is_the_only_initial_phase(self):
        self.assertEqual(audit.reachable_phases([]), {0})
        rows = [smart_row(1, 0, mask=0x800)]
        self.assertEqual(audit.reachable_phases(rows), {0})
        self.assertEqual(len(audit.check_c06({"smart": rows})), 1)

    def test_blocks_are_independent(self):
        rows = [smart_row(10, 0, action=22, params=(2,)),
                smart_row(20, 0, mask=0x2)]
        findings = audit.check_c06({"smart": rows})
        self.assertEqual([finding.location for finding in findings], ["20:0"])

    def test_timed_action_lists_fold_called_phases(self):
        calls = [smart_row(1, 0, action=80, params=(7,)),
                 smart_row(1, 1, action=87, params=(8, 9)),
                 smart_row(1, 2, action=88, params=(10, 11))]
        script9 = [smart_row(7, 0, source_type=9, action=22, params=(2,)),
                   smart_row(8, 0, source_type=9, action=22, params=(3,)),
                   smart_row(9, 0, source_type=9, action=22, params=(4,)),
                   smart_row(10, 0, source_type=9, action=22, params=(5,)),
                   smart_row(11, 0, source_type=9, action=22, params=(6,))]
        masks = [smart_row(1, 10 + phase, mask=1 << (phase - 1)) for phase in range(2, 7)]
        timed = {row["entryorguid"]: [row] for row in script9}
        self.assertEqual(audit.reachable_phases(calls, timed=timed),
                         {0, 2, 3, 4, 5, 6})
        self.assertEqual(audit.check_c06({"smart": calls + script9 + masks}), [])

    def test_timed_action_list_rows_use_the_caller_phase(self):
        rows = [smart_row(1, 0, action=80, params=(7,)),
                smart_row(7, 0, source_type=9, mask=0x2, action=22, params=(3,))]
        self.assertEqual(audit.reachable_phases(rows[:1], timed={7: rows[1:]}), {0})

    def test_timed_action_list_row_runs_in_reached_caller_phase(self):
        rows = [smart_row(1, 0, action=22, params=(2,)),
                smart_row(1, 1, mask=0x2, action=80, params=(7,)),
                smart_row(7, 0, source_type=9, mask=0x2, action=22, params=(3,))]
        timed = {7: rows[2:]}
        self.assertEqual(audit.reachable_phases(rows[:2], timed=timed), {0, 2, 3})
        self.assertEqual(audit.check_c06({"smart": rows}), [])

    def test_fixed_guid_timed_target_suppresses_target_block(self):
        rows = [smart_row(1, 0, action=80, target=10, target_param1=55),
                smart_row(200, 0, mask=0x2)]
        data = {"smart": rows, "creature_spawn_map": {55: 200}}
        self.assertEqual(audit.check_c06(data), [])

    def test_fixed_guid_timed_target_does_not_change_caller_phase(self):
        rows = [smart_row(1, 0, action=80, params=(7,), target=14, target_param1=55),
                smart_row(1, 1, mask=0x2),
                smart_row(7, 0, source_type=9, action=22, params=(2,))]
        data = {"smart": rows, "go_spawn_map": {55: 300}}
        causes = " ".join(finding.cause for finding in audit.check_c06(data))
        self.assertIn("id 1 phase mask 0x2 is not reachable", causes)

    def test_script9_fixed_guid_target_suppresses_target_block(self):
        rows = [smart_row(1, 0, action=80, params=(7,)),
                smart_row(7, 0, source_type=9, action=80, target=10, target_param1=55),
                smart_row(200, 0, mask=0x2)]
        data = {"smart": rows, "creature_spawn_map": {55: 200}}
        self.assertEqual(audit.check_c06(data), [])

    def test_uninvoked_script9_fixed_guid_target_does_not_suppress(self):
        rows = [smart_row(1, 0, mask=0x2),
                smart_row(7, 0, source_type=9, action=80, target=10, target_param1=55),
                smart_row(200, 0, mask=0x2)]
        data = {"smart": rows, "creature_spawn_map": {55: 200}}
        locations = [finding.location for finding in audit.check_c06(data)]
        self.assertIn("1:0", locations)
        self.assertIn("200:0", locations)

    def test_timed_action_list_cycle_terminates(self):
        rows = [smart_row(1, 0, action=80, params=(7,)),
                smart_row(7, 0, source_type=9, action=80, params=(7,)),
                smart_row(7, 1, source_type=9, action=22, params=(2,))]
        self.assertEqual(audit.reachable_phases(rows[:1], timed={7: rows[1:]}), {0, 2})
        self.assertEqual(audit.check_c06({"smart": rows}), [])

    def test_timed_action_list_blocks_are_not_reported_standalone(self):
        rows = [smart_row(7, 0, source_type=9, mask=0x4),
                smart_row(7, 1, source_type=9, link=9)]
        findings = audit.check_c06({"smart": rows})
        self.assertEqual([finding.cause for finding in findings],
                         ["id 1 links to missing id 9"])

    def test_install_ai_template_unlocks_phase_one(self):
        for template in (1, 5):
            with self.subTest(template=template):
                rows = [smart_row(1, 0, action=58, params=(template,)),
                        smart_row(1, 1, mask=0x1)]
                self.assertEqual(audit.reachable_phases(rows), {0, 1})
                self.assertEqual(audit.check_c06({"smart": rows}), [])

    def test_other_ai_templates_do_not_unlock_phase_one(self):
        rows = [smart_row(1, 0, action=58, params=(2,)),
                smart_row(1, 1, mask=0x1)]
        self.assertEqual(audit.reachable_phases(rows), {0})
        self.assertEqual(len(audit.check_c06({"smart": rows})), 1)


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


class CheckC13Test(unittest.TestCase):
    def test_flags_missing_gossip_and_quest_sources(self):
        data = {
            "conditions": [(14, 10, 20), (14, 11, 21), (15, 10, 2), (19, 0, 99), (19, 0, 98)],
            "gossip_menus": {(10, 20)},
            "gossip_options": set(),
            "quest_ids": {99},
        }
        findings = audit.check_c13(data)
        kinds = sorted(finding.entity_kind for finding in findings)
        self.assertEqual(kinds, ["gossip_menu", "gossip_option", "quest"])
        causes = " ".join(finding.cause for finding in findings)
        self.assertIn("TextID 21", causes)
        self.assertIn("OptionID 2", causes)
        self.assertIn("missing quest", causes)


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
