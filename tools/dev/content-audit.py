#!/usr/bin/env python3
"""Read-only content audit for the AzerothCore world database.

Implements checks C-01 to C-13 from specs/content-pipeline.md. It never writes
to the database: every query is a SELECT and the database name must end in
"_world" (production or test).

Exit codes:
    0  no unwaived blocker findings
    1  at least one unwaived blocker finding
    2  tool, configuration, or database error
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

SEVERITY_ORDER = {"blocker": 0, "major": 1, "minor": 2}
LEVEL_BANDS = ((1, 20), (21, 40), (41, 60), (61, 70), (71, 80), (81, 255))

# creature_template.npcflag bits
NPC_FLAG_QUESTGIVER = 0x02
NPC_FLAG_TRAINER = 0x10
NPC_FLAG_VENDOR = 0x80

LOOT_TABLES = (
    "creature_loot_template",
    "disenchant_loot_template",
    "fishing_loot_template",
    "gameobject_loot_template",
    "item_loot_template",
    "mail_loot_template",
    "milling_loot_template",
    "pickpocketing_loot_template",
    "player_loot_template",
    "prospecting_loot_template",
    "reference_loot_template",
    "skinning_loot_template",
    "spell_loot_template",
)


class AuditError(RuntimeError):
    """Configuration or database failure. Maps to exit code 2."""


@dataclass(frozen=True)
class Finding:
    check: str
    severity: str
    entity_kind: str
    entity_id: int
    location: str
    cause: str
    quest_id: int = 0

    def sort_key(self):
        return (SEVERITY_ORDER.get(self.severity, 9), self.check, self.entity_kind,
                self.entity_id, self.location)

    def as_dict(self):
        payload = {
            "check": self.check,
            "severity": self.severity,
            "entity_kind": self.entity_kind,
            "entity_id": self.entity_id,
            "location": self.location,
            "cause": self.cause,
        }
        if self.quest_id:
            payload["quest_id"] = self.quest_id
        return payload

    def waiver_key(self):
        return (self.check, self.entity_kind, self.entity_id)


# ---------------------------------------------------------------- database ---

def parse_world_dsn(path: Path) -> dict[str, str]:
    """Read WorldDatabaseInfo from a worldserver.conf style file."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise AuditError(f"cannot read config {path}: {exc}") from exc
    match = re.search(r'(?m)^\s*WorldDatabaseInfo\s*=\s*"([^"]*)"', text)
    if not match:
        raise AuditError(f"WorldDatabaseInfo not found in {path}")
    parts = match.group(1).split(";")
    if len(parts) != 5:
        raise AuditError(f"WorldDatabaseInfo has {len(parts)} fields, expected 5")
    host, port, user, password, database = parts
    return {
        "host": os.environ.get("CONTENT_AUDIT_DB_HOST", host),
        "port": os.environ.get("CONTENT_AUDIT_DB_PORT", port),
        "user": os.environ.get("CONTENT_AUDIT_DB_USER", user),
        "password": os.environ.get("CONTENT_AUDIT_DB_PASSWORD", password),
        "database": os.environ.get("CONTENT_AUDIT_DB_NAME", database),
    }


def parse_data_dir(path: Path) -> Path | None:
    """Read DataDir from a worldserver.conf style file."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    match = re.search(r'(?m)^\s*DataDir\s*=\s*"([^"]*)"', text)
    return Path(match.group(1)) if match else None


def dbc_ids(path: Path) -> set[int]:
    """First field of every record in a WDBC file, treated as the id."""
    with path.open("rb") as handle:
        header = handle.read(20)
        if len(header) != 20:
            raise AuditError(f"{path} is too short to be a DBC file")
        magic, record_count, _, record_size, _ = struct.unpack("<4sIIII", header)
        if magic != b"WDBC":
            raise AuditError(f"{path} is not a DBC file")
        payload = handle.read(record_count * record_size)
    if len(payload) != record_count * record_size:
        raise AuditError(f"{path} is truncated")
    return {struct.unpack_from("<I", payload, index * record_size)[0]
            for index in range(record_count)}


def ensure_world_database(database: str) -> None:
    if not database.endswith("_world"):
        raise AuditError(
            f"refusing database {database!r}: name must end with '_world'")


class Db:
    """Minimal read-only client over the mysql command line."""

    def __init__(self, dsn: dict[str, str]):
        self.dsn = dsn
        self.binary = shutil.which("mysql")
        if not self.binary:
            raise AuditError("mysql client not found in PATH")
        ensure_world_database(dsn["database"])

    def query(self, sql: str) -> list[list[str]]:
        stripped = sql.lstrip().upper()
        if not (stripped.startswith("SELECT") or stripped.startswith("WITH")):
            raise AuditError("refusing non-SELECT statement")
        command = [
            self.binary, "-h", self.dsn["host"], "-P", self.dsn["port"],
            "-u", self.dsn["user"], "-D", self.dsn["database"],
            "--batch", "--skip-column-names", "--default-character-set=utf8mb4",
            "-e", sql,
        ]
        env = os.environ.copy()
        env["MYSQL_PWD"] = self.dsn["password"]
        try:
            result = subprocess.run(command, capture_output=True, text=True,
                                    env=env, timeout=300, check=False)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise AuditError(f"database query failed: {exc}") from exc
        if result.returncode != 0:
            message = result.stderr.strip().splitlines()
            raise AuditError("database query failed: " +
                             (message[-1] if message else "unknown error"))
        rows = []
        for line in result.stdout.splitlines():
            rows.append([("" if value == "NULL" else value) for value in line.split("\t")])
        return rows

    def one(self, sql: str) -> str:
        rows = self.query(sql)
        return rows[0][0] if rows else ""

    def strings(self, sql: str) -> set[str]:
        return {row[0] for row in self.query(sql) if row and row[0]}

    def integers(self, sql: str) -> set[int]:
        values = set()
        for row in self.query(sql):
            if row and row[0]:
                values.add(int(row[0]))
        return values


# ---------------------------------------------------------------- helpers ---

def intellig(value) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def enum_max_value(text: str, name: str) -> int | None:
    """Maximum explicit or implied enumerator value of one enum body, or None."""
    match = re.search(rf"\benum\s+{name}\b[^{{]*{{(.*?)}};", text, re.S)
    if not match:
        return None
    body = re.sub(r"//[^\n]*", "", match.group(1))
    value: int | None = -1
    maximum: int | None = None
    for entry in body.split(","):
        entry = re.sub(r"//.*", "", entry).strip()
        if not entry:
            continue
        if "=" in entry:
            rhs = entry.split("=", 1)[1].strip()
            try:
                value = int(rhs, 0)
            except ValueError:
                value = None
        elif value is not None:
            value += 1
        if value is not None and (maximum is None or value > maximum):
            maximum = value
    return None if maximum is None else maximum


def smart_limits(header: Path) -> dict[str, int]:
    """Valid type counts and phase-mask limit, read from the source header."""
    try:
        text = header.read_text(encoding="utf-8")
    except OSError as exc:
        raise AuditError(f"cannot read {header}: {exc}") from exc
    limits = {}
    for kind, enum_name in (("event", "SMART_EVENT"),
                            ("action", "SMART_ACTION"),
                            ("target", "SMARTAI_TARGETS")):
        maximum = enum_max_value(text, enum_name)
        if maximum is not None:
            limits[kind] = maximum + 1
    phase_bits = [int(value) for value in
                  re.findall(r"SMART_EVENT_PHASE_\d+_BIT\s*=\s*(\d+)", text)]
    if phase_bits:
        limits["phase_mask"] = sum(phase_bits)
    return limits


def script_tokens(root: Path) -> set[str]:
    """Identifiers that appear in content script sources."""
    tokens: set[str] = set()
    pattern = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
    for path in (root / "src" / "server" / "scripts").rglob("*"):
        if path.suffix not in {".cpp", ".h"}:
            continue
        try:
            tokens.update(pattern.findall(path.read_text(encoding="utf-8",
                                                          errors="ignore")))
        except OSError:
            continue
    return tokens


def in_band(level: int, low: int, high: int) -> bool:
    return low <= level <= high


# ------------------------------------------------------------------ checks ---

def check_c01(data: dict) -> list[Finding]:
    findings = []
    sources = (("creature", "creature_queststarter", "creature_template", "entry", data["creature_entries"]),
               ("gameobject", "gameobject_queststarter", "gameobject_template", "entry", data["go_entries"]))
    for kind, table, template, column, entries in sources:
        for giver, quest in data["starters"][table]:
            if giver not in entries:
                findings.append(Finding("C-01", "blocker", kind, giver, table,
                                        f"{table} references missing {template}.{column}"))
            if quest not in data["quest_ids"]:
                findings.append(Finding("C-01", "blocker", "quest", quest, table,
                                        f"{table} references missing quest_template.ID"))
    for kind, table, entries in (
            ("creature", "creature_questender", data["creature_entries"]),
            ("gameobject", "gameobject_questender", data["go_entries"])):
        for giver, quest in data["enders"][table]:
            if giver not in entries:
                findings.append(Finding("C-01", "blocker", kind, giver, table,
                                        f"{table} references a missing entry"))
            if quest not in data["quest_ids"]:
                findings.append(Finding("C-01", "blocker", "quest", quest, table,
                                        f"{table} references missing quest_template.ID"))
    return findings


def check_c02(data: dict) -> list[Finding]:
    findings = []
    for quest in data["quests"]:
        for slot in range(1, 5):
            target = quest["npcs"][slot - 1]
            if target == 0:
                continue
            wanted = abs(target)
            if target > 0:
                if wanted not in data["creature_entries"]:
                    severity = "blocker"
                    cause = "objective creature has no creature_template"
                elif wanted not in data["creature_spawns"]:
                    severity = "minor"
                    cause = "objective creature has no spawn (may be summoned or scripted)"
                else:
                    continue
                kind = "creature"
            else:
                if wanted not in data["go_entries"]:
                    severity = "blocker"
                    cause = "objective gameobject has no gameobject_template"
                elif wanted not in data["go_spawns"]:
                    severity = "minor"
                    cause = "objective gameobject has no spawn (may be summoned or scripted)"
                else:
                    continue
                kind = "gameobject"
            findings.append(Finding("C-02", severity, kind, wanted,
                                    f"quest {quest['id']}", cause,
                                    quest_id=quest["id"]))
    return findings


def check_c03(data: dict) -> list[Finding]:
    findings = []
    quests = {quest["id"]: quest for quest in data["quests"]}
    for quest in data["quests"]:
        if quest["min_level"] > quest["level"] > 0:
            findings.append(Finding("C-03", "minor", "quest", quest["id"],
                                    "quest_template",
                                    f"MinLevel {quest['min_level']} exceeds QuestLevel {quest['level']}"))
        for field, label in (("prev", "PrevQuestID"), ("next", "NextQuestID")):
            value = quest[field]
            if value and abs(value) not in quests:
                findings.append(Finding("C-03", "blocker", "quest", quest["id"],
                                        "quest_template_addon",
                                        f"{label} points at missing quest {abs(value)}"))
    # cycles over positive PrevQuestID edges
    state: dict[int, int] = {}
    for start in quests:
        if state.get(start):
            continue
        path = []
        node = start
        while node in quests and not state.get(node):
            state[node] = 1
            path.append(node)
            prev = quests[node]["prev"]
            node = prev if prev > 0 else 0
        if node in path:
            cycle = path[path.index(node):]
            findings.append(Finding("C-03", "blocker", "quest", min(cycle),
                                    "quest_template_addon",
                                    "prerequisite cycle: " + " -> ".join(map(str, cycle))))
        for visited in path:
            state[visited] = 2
    return findings


def check_c04(data: dict) -> list[Finding]:
    findings = []
    for quest in data["quests"]:
        for item in quest["items"]:
            if item == 0:
                continue
            if item not in data["item_entries"]:
                findings.append(Finding("C-04", "blocker", "item", item,
                                        f"quest {quest['id']}",
                                        "required item missing from item_template",
                                        quest_id=quest["id"]))
            elif item not in data["item_sources"]:
                findings.append(Finding("C-04", "minor", "item", item,
                                        f"quest {quest['id']}",
                                        "required item has no known loot, vendor, or quest source",
                                        quest_id=quest["id"]))
    return findings


def check_c05(data: dict) -> list[Finding]:
    findings = []
    limits = data["smart_limits"]
    if not limits:
        return findings
    for row in data["smart"]:
        block = f"{row['entryorguid']}:{row['source_type']}"
        for kind in ("event", "action", "target"):
            value = row[kind]
            limit = limits.get(kind)
            if limit is not None and value >= limit:
                findings.append(Finding("C-05", "major", "smart_script",
                                        row["entryorguid"], block,
                                        f"{kind}_type {value} is outside 0..{limit - 1}"))
        if row["chance"] > 100:
            findings.append(Finding("C-05", "major", "smart_script",
                                    row["entryorguid"], block,
                                    f"event_chance {row['chance']} exceeds 100"))
        if row["phase_mask"] > limits.get("phase_mask", 4095):
            findings.append(Finding("C-05", "major", "smart_script",
                                    row["entryorguid"], block,
                                    f"event_phase_mask {row['phase_mask']} exceeds supported bits"))
    return findings


def check_c06(data: dict) -> list[Finding]:
    findings = []
    blocks: dict[tuple[int, int], dict[int, int]] = {}
    for row in data["smart"]:
        blocks.setdefault((row["entryorguid"], row["source_type"]), {})[row["id"]] = row["link"]
    for (entry, source), links in blocks.items():
        block = f"{entry}:{source}"
        for row_id, link in links.items():
            if link and link not in links:
                findings.append(Finding("C-06", "major", "smart_script", entry, block,
                                        f"id {row_id} links to missing id {link}"))
            if link == row_id and row_id != 0:
                findings.append(Finding("C-06", "major", "smart_script", entry, block,
                                        f"id {row_id} links to itself"))
        for start in links:
            seen = set()
            node = start
            cycle = None
            while node in links and links[node]:
                if node in seen:
                    cycle = node
                    break
                seen.add(node)
                node = links[node]
            if cycle is not None:
                findings.append(Finding("C-06", "major", "smart_script", entry, block,
                                        f"link cycle through id {cycle}"))
                break
    return findings


def _sai_entries(data: dict, source_type: int, spawn_map: dict[int, int]) -> set[int]:
    """Entries with SmartAI rows, resolving per-spawn scripts keyed by -guid."""
    entries = set()
    for row in data["smart"]:
        if row["source_type"] != source_type:
            continue
        key = row["entryorguid"]
        if key >= 0:
            entries.add(key)
        else:
            owner = spawn_map.get(-key)
            if owner:
                entries.add(owner)
    return entries


def check_c07(data: dict) -> list[Finding]:
    findings = []
    creature_sai = _sai_entries(data, 0, data["creature_spawn_map"])
    go_sai = _sai_entries(data, 1, data["go_spawn_map"])
    for entry in sorted(data["creature_ai_smart"] - creature_sai):
        findings.append(Finding("C-07", "major", "creature", entry,
                                "creature_template", "AIName=SmartAI but no source_type 0 rows"))
    for entry in sorted(creature_sai - data["creature_ai_smart"]):
        if entry in data["creature_entries"]:
            findings.append(Finding("C-07", "major", "creature", entry,
                                    "smart_scripts", "source_type 0 rows without AIName=SmartAI"))
    for entry in sorted(data["go_ai_smart"] - go_sai):
        findings.append(Finding("C-07", "major", "gameobject", entry,
                                "gameobject_template", "AIName=SmartGameObjectAI but no source_type 1 rows"))
    for entry in sorted(go_sai - data["go_ai_smart"]):
        if entry in data["go_entries"]:
            findings.append(Finding("C-07", "major", "gameobject", entry,
                                    "smart_scripts",
                                    "source_type 1 rows without AIName=SmartGameObjectAI"))
    return findings


def check_c08(data: dict) -> list[Finding]:
    findings = []
    for kind, name, entity_id in sorted(data["script_names"]):
        if name not in data["tokens"]:
            findings.append(Finding("C-08", "blocker", kind, entity_id, name,
                                    "ScriptName not registered in src/server/scripts"))
    return findings


def check_c09(data: dict) -> list[Finding]:
    findings = []
    for map_id, script in data["instance_scripts"]:
        if script and script not in data["tokens"]:
            findings.append(Finding("C-09", "blocker", "instance", map_id, script,
                                    "instance_template.script not registered"))
    return findings


def check_c10(data: dict) -> list[Finding]:
    findings = []
    for kind, spawns, templates, table in (
            ("creature", data["creature_spawns"], data["creature_entries"], "creature"),
            ("gameobject", data["go_spawns"], data["go_entries"], "gameobject")):
        for entry in sorted(spawns - templates):
            findings.append(Finding("C-10", "blocker", kind, entry, table,
                                    f"spawn of missing {table}_template entry"))
    for guid, kind in data["zero_spawnmask"]:
        findings.append(Finding("C-10", "major", kind, guid, "spawnMask",
                                "spawnMask is 0, spawn never appears"))
    return findings


def check_c11(data: dict) -> list[Finding]:
    findings = []
    # A flag without stock or assignment is cosmetic: the core opens an empty vendor window or
    # nothing for a trainer. Editing NPC flags without sniffs risks breaking scripted vendors, so
    # it is data hygiene, not breakage.
    for entry in sorted(data["vendor_flag"] - data["vendor_rows"]):
        findings.append(Finding("C-11", "minor", "creature", entry,
                                "creature_template.npcflag",
                                "vendor flag set but npc_vendor has no rows"))
    for entry, item in data["vendor_items"]:
        if item > 0 and item not in data["item_entries"]:
            findings.append(Finding("C-11", "blocker", "item", item,
                                    f"npc_vendor {entry}",
                                    "vendor sells missing item_template entry"))
    trainer_ready = {creature for creature, trainer in data["creature_trainer"].items()
                     if trainer in data["trainer_rows"]}
    for entry in sorted(data["trainer_flag"] - trainer_ready):
        findings.append(Finding("C-11", "minor", "creature", entry,
                                "creature_template.npcflag",
                                "trainer flag set but no creature_default_trainer or trainer_spell rows"))
    for trainer, spell in data["trainer_spells"]:
        if spell > 0 and spell not in data["spell_entries"]:
            findings.append(Finding("C-11", "major", "trainer", trainer, "trainer_spell",
                                    f"trainer teaches missing Spell.dbc spell {spell}"))
    return findings


def check_c12(data: dict) -> list[Finding]:
    findings = []
    for table, items in data["loot_items"].items():
        for item in items:
            if item not in data["item_entries"]:
                findings.append(Finding("C-12", "blocker", "item", item, table,
                                        "loot references missing item_template entry"))
    for table, ref in data["loot_refs"]:
        if ref not in data["reference_entries"]:
            findings.append(Finding("C-12", "major", "reference_loot", ref, table,
                                    "loot references missing reference_loot_template entry"))
    return findings


def check_c13(data: dict) -> list[Finding]:
    findings = []
    for source, group, entry in data["conditions"]:
        if source == 14:
            if (group, entry) not in data["gossip_menus"]:
                findings.append(Finding("C-13", "major", "gossip_menu", group,
                                        "conditions", f"condition for missing gossip_menu "
                                        f"MenuID {group} TextID {entry}"))
        elif source == 15:
            if (group, entry) not in data["gossip_options"]:
                findings.append(Finding("C-13", "major", "gossip_option", group,
                                        "conditions", f"condition for missing gossip_menu_option "
                                        f"MenuID {group} OptionID {entry}"))
        elif source == 19 and entry not in data["quest_ids"]:
            findings.append(Finding("C-13", "major", "quest", entry, "conditions",
                                    "QUEST_AVAILABLE condition references missing quest"))
    return findings


CHECKS = (
    check_c01, check_c02, check_c03, check_c04, check_c05, check_c06,
    check_c07, check_c08, check_c09, check_c10, check_c11, check_c12, check_c13,
)


# ------------------------------------------------------------------- data ----

def load_data(db: Db, root: Path, data_dir: Path | None) -> dict:
    data: dict = {}

    data["creature_entries"] = db.integers("SELECT entry FROM creature_template")
    data["go_entries"] = db.integers("SELECT entry FROM gameobject_template")
    data["item_entries"] = db.integers("SELECT entry FROM item_template")
    spell_dbc_path = data_dir / "dbc" / "Spell.dbc" if data_dir else None
    if not spell_dbc_path or not spell_dbc_path.exists():
        raise AuditError(
            f"Spell.dbc not found at {spell_dbc_path or 'DataDir'}; "
            "set DataDir in the config or pass --data-dir")
    data["spell_entries"] = dbc_ids(spell_dbc_path)
    data["spell_source"] = str(spell_dbc_path)
    data["quest_ids"] = db.integers("SELECT ID FROM quest_template")
    data["creature_spawns"] = db.integers("SELECT DISTINCT id FROM creature")
    data["go_spawns"] = db.integers("SELECT DISTINCT id FROM gameobject")
    data["creature_spawn_map"] = {int(guid): int(entry) for guid, entry in
                                  db.query("SELECT guid, id FROM creature")}
    data["go_spawn_map"] = {int(guid): int(entry) for guid, entry in
                            db.query("SELECT guid, id FROM gameobject")}
    data["reference_entries"] = db.integers("SELECT Entry FROM reference_loot_template")
    data["gossip_menus"] = {
        (int(row[0]), int(row[1])) for row in
        db.query("SELECT DISTINCT gm.MenuID, gm.TextID FROM gossip_menu gm "
                 "JOIN npc_text nt ON nt.ID = gm.TextID AND nt.ID <> 0")}
    data["gossip_options"] = {
        (int(row[0]), int(row[1])) for row in
        db.query("SELECT DISTINCT MenuID, OptionID FROM gossip_menu_option")}
    data["conditions"] = {
        (int(row[0]), int(row[1]), int(row[2])) for row in
        db.query("SELECT SourceTypeOrReferenceId, SourceGroup, SourceEntry FROM conditions "
                 "WHERE SourceTypeOrReferenceId IN (14, 15, 19)")}

    data["starters"] = {}
    data["enders"] = {}
    for table in ("creature_queststarter", "gameobject_queststarter"):
        data["starters"][table] = [
            (int(a), int(b)) for a, b in
            (row[:2] for row in db.query(f"SELECT id, quest FROM {table}"))]
    for table in ("creature_questender", "gameobject_questender"):
        data["enders"][table] = [
            (int(a), int(b)) for a, b in
            (row[:2] for row in db.query(f"SELECT id, quest FROM {table}"))]

    quest_sql = """
        SELECT q.ID, q.QuestLevel, q.MinLevel, q.StartItem,
               q.RequiredNpcOrGo1, q.RequiredNpcOrGo2, q.RequiredNpcOrGo3, q.RequiredNpcOrGo4,
               q.RequiredItemId1, q.RequiredItemId2, q.RequiredItemId3,
               q.RequiredItemId4, q.RequiredItemId5, q.RequiredItemId6,
               a.PrevQuestID, a.NextQuestID
        FROM quest_template q
        LEFT JOIN quest_template_addon a ON a.ID = q.ID
    """
    data["quests"] = []
    for row in db.query(quest_sql):
        values = [intellig(value) for value in row[:16]]
        data["quests"].append({
            "id": values[0], "level": values[1], "min_level": values[2],
            "start_item": values[3],
            "npcs": values[4:8], "items": values[8:14],
            "prev": values[14], "next": values[15],
        })

    data["creature_ai_smart"] = db.integers(
        "SELECT entry FROM creature_template WHERE AIName = 'SmartAI'")
    data["go_ai_smart"] = db.integers(
        "SELECT entry FROM gameobject_template WHERE AIName = 'SmartGameObjectAI'")
    data["smart"] = []
    for row in db.query("""
            SELECT entryorguid, source_type, id, link, event_type, action_type, target_type,
                   event_chance, event_phase_mask
            FROM smart_scripts"""):
        data["smart"].append({
            "entryorguid": intellig(row[0]), "source_type": intellig(row[1]),
            "id": intellig(row[2]), "link": intellig(row[3]),
            "event": intellig(row[4]), "action": intellig(row[5]),
            "target": intellig(row[6]), "chance": intellig(row[7]),
            "phase_mask": intellig(row[8]),
        })

    data["script_names"] = set()
    for kind, table, id_column in (
            ("creature", "creature_template", "entry"),
            ("gameobject", "gameobject_template", "entry"),
            ("creature_spawn", "creature", "guid"),
            ("gameobject_spawn", "gameobject", "guid")):
        for row in db.query(f"SELECT {id_column}, ScriptName FROM {table} "
                            f"WHERE ScriptName <> ''"):
            data["script_names"].add((kind, row[1], intellig(row[0])))
    data["instance_scripts"] = [
        (int(row[0]), row[1]) for row in
        db.query("SELECT map, script FROM instance_template WHERE script <> ''")]
    data["tokens"] = script_tokens(root)
    data["smart_limits"] = smart_limits(
        root / "src" / "server" / "game" / "AI" / "SmartScripts" / "SmartScriptMgr.h")

    data["zero_spawnmask"] = []
    for kind, table in (("creature", "creature"), ("gameobject", "gameobject")):
        for row in db.query(f"SELECT guid FROM {table} WHERE spawnMask = 0"):
            data["zero_spawnmask"].append((int(row[0]), kind))

    vendor_flag = db.integers(
        "SELECT entry FROM creature_template WHERE npcflag & 128")
    trainer_flag = db.integers(
        "SELECT entry FROM creature_template WHERE npcflag & 16")
    data["vendor_flag"] = vendor_flag
    data["trainer_flag"] = trainer_flag
    vendor_rows = db.integers("SELECT DISTINCT entry FROM npc_vendor")
    vendor_rows |= db.integers(
        "SELECT DISTINCT c.id FROM game_event_npc_vendor e "
        "JOIN creature c ON c.guid = e.guid")
    data["vendor_rows"] = vendor_rows
    data["vendor_items"] = [
        (int(row[0]), int(row[1])) for row in
        db.query("SELECT entry, item FROM npc_vendor")]
    data["vendor_items"] += [
        (int(row[0]), int(row[1])) for row in
        db.query("SELECT DISTINCT c.id, e.item FROM game_event_npc_vendor e "
                 "JOIN creature c ON c.guid = e.guid")]
    data["creature_trainer"] = {
        int(creature): int(trainer) for creature, trainer in
        db.query("SELECT CreatureId, TrainerId FROM creature_default_trainer")}
    data["trainer_spells"] = [
        (int(row[0]), int(row[1])) for row in
        db.query("SELECT TrainerId, SpellId FROM trainer_spell")]
    data["trainer_rows"] = {trainer for trainer, _ in data["trainer_spells"]}

    data["loot_items"] = {}
    data["loot_refs"] = []
    for table in LOOT_TABLES:
        data["loot_items"][table] = db.integers(
            f"SELECT DISTINCT Item FROM {table} WHERE Item > 0 AND Reference = 0")
        for row in db.query(
                f"SELECT DISTINCT Reference FROM {table} WHERE Reference > 0"):
            data["loot_refs"].append((table, int(row[0])))

    sources: set[int] = set()
    for table in LOOT_TABLES:
        sources |= db.integers(
            f"SELECT DISTINCT Item FROM {table} WHERE Item > 0 AND Reference = 0")
    sources |= db.integers("SELECT item FROM npc_vendor WHERE item > 0")
    sources |= db.integers("SELECT item FROM game_event_npc_vendor WHERE item > 0")
    sources |= db.integers("SELECT ItemId FROM creature_questitem WHERE ItemId > 0")
    sources |= db.integers("SELECT ItemId FROM gameobject_questitem WHERE ItemId > 0")
    sources |= db.integers(
        "SELECT StartItem FROM quest_template WHERE StartItem > 0")
    for index in range(1, 5):
        sources |= db.integers(
            f"SELECT RewardItem{index} FROM quest_template WHERE RewardItem{index} > 0")
    for index in range(1, 7):
        sources |= db.integers(
            f"SELECT RewardChoiceItemID{index} FROM quest_template "
            f"WHERE RewardChoiceItemID{index} > 0")
    data["item_sources"] = sources
    return data


# ---------------------------------------------------------------- waivers ----

def load_waivers(path: Path) -> list[dict]:
    if not path.exists():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AuditError(f"cannot read waivers {path}: {exc}") from exc
    waivers = payload.get("waivers", [])
    if not isinstance(waivers, list):
        raise AuditError(f"waivers in {path} must be a list")
    for index, waiver in enumerate(waivers):
        if not isinstance(waiver, dict):
            raise AuditError(f"waiver {index} must be an object")
        for field in ("check", "entity_kind", "entity_id", "reason", "accepted_by"):
            if waiver.get(field) in (None, ""):
                raise AuditError(f"waiver {index} is missing {field}")
    return waivers


def apply_waivers(findings: list[Finding], waivers: list[dict]):
    """Split findings into kept and waived, and report stale waivers."""
    keys = {}
    for index, waiver in enumerate(waivers):
        try:
            key = (waiver["check"], waiver["entity_kind"], int(waiver["entity_id"]))
        except (KeyError, TypeError, ValueError) as exc:
            raise AuditError(f"waiver {index} is malformed: {exc}") from exc
        if key in keys:
            raise AuditError(f"duplicate waiver for {key}")
        keys[key] = waiver
    kept, waived = [], []
    for finding in findings:
        waiver = keys.pop(finding.waiver_key(), None)
        if waiver is None:
            kept.append(finding)
        else:
            waived.append((finding, waiver))
    stale = list(keys.values())
    return kept, waived, stale


# --------------------------------------------------------------- coverage ----

def coverage(data: dict, findings: list[Finding]) -> dict:
    blocked_quests = {finding.quest_id for finding in findings
                      if finding.check in {"C-02", "C-04"} and finding.quest_id}
    starters = {quest for _, quest in data["starters"]["creature_queststarter"]}
    starters |= {quest for _, quest in data["starters"]["gameobject_queststarter"]}
    rows = []
    for low, high in LEVEL_BANDS:
        band = [quest for quest in data["quests"] if in_band(quest["level"], low, high)]
        if not band:
            continue
        covered = 0
        for quest in band:
            has_start = quest["id"] in starters or quest["start_item"] > 0
            if has_start and quest["id"] not in blocked_quests:
                covered += 1
        percent = round(100.0 * covered / len(band), 2)
        rows.append({"band": f"{low}-{high}", "quests": len(band),
                     "covered": covered, "percent": percent})
    total_quests = sum(row["quests"] for row in rows)
    total_covered = sum(row["covered"] for row in rows)
    if total_quests:
        rows.append({"band": "overall", "quests": total_quests,
                     "covered": total_covered,
                     "percent": round(100.0 * total_covered / total_quests, 2)})
    return {"bands": rows}


# ------------------------------------------------------------------ report ---

def render_markdown(result: dict, limit: int) -> str:
    findings = result["findings"]
    counts = {severity: sum(1 for f in findings if f["severity"] == severity)
              for severity in SEVERITY_ORDER}
    lines = [
        "# Content audit",
        "",
        f"- Generated: {result['generatedAt']}",
        f"- Database: `{result['database']}` (source version `{result['sourceVersion']}`)",
        f"- Findings: {counts['blocker']} blocker, {counts['major']} major, "
        f"{counts['minor']} minor",
        f"- Waived: {len(result['waived'])}; stale waivers: {len(result['staleWaivers'])}",
        "",
        "## Coverage",
        "",
        "| Band | Quests | Covered | Percent |",
        "|------|--------|---------|---------|",
    ]
    for row in result["coverage"]["bands"]:
        lines.append(f"| {row['band']} | {row['quests']} | {row['covered']} | "
                     f"{row['percent']}% |")
    lines += ["", "## Findings", ""]
    if not findings:
        lines.append("No unwaived findings.")
    else:
        lines += ["| Check | Severity | Entity | Location | Cause |",
                  "|-------|----------|--------|----------|-------|"]
        for finding in findings[:limit]:
            lines.append("| {check} | {severity} | {kind} {id} | {location} | {cause} |".format(
                check=finding["check"], severity=finding["severity"],
                kind=finding["entity_kind"], id=finding["entity_id"],
                location=finding["location"], cause=finding["cause"]))
        if len(findings) > limit:
            lines.append("")
            lines.append(f"Showing {limit} of {len(findings)} findings; "
                         "use `--json` for the full report.")
    if result["warnings"]:
        lines += ["", "## Warnings", ""]
        lines += [f"- {warning}" for warning in result["warnings"]]
    if result["staleWaivers"]:
        lines += ["", "## Stale waivers", ""]
        for waiver in result["staleWaivers"]:
            lines.append(f"- {waiver.get('check')} {waiver.get('entity_kind')} "
                         f"{waiver.get('entity_id')}: {waiver.get('reason', '')}")
    return "\n".join(lines) + "\n"


# -------------------------------------------------------------------- main ---

def run(config: Path, root: Path, waiver_path: Path,
        data_dir_override: Path | None = None) -> dict:
    db = Db(parse_world_dsn(config))
    data_dir = data_dir_override or parse_data_dir(config)
    if not data_dir:
        raise AuditError("DataDir is not configured; set it in the config or pass --data-dir")
    data = load_data(db, root, data_dir)
    findings = []
    for check in CHECKS:
        findings.extend(check(data))
    findings.sort(key=Finding.sort_key)

    waivers = load_waivers(waiver_path)
    kept, waived, stale = apply_waivers(findings, waivers)

    version = db.query("SELECT core_version, db_version FROM version LIMIT 1")
    source_version = version[0][1] if version and len(version[0]) > 1 else "unknown"

    warnings = []
    if not data["smart_limits"]:
        warnings.append("SmartAI limits not parsed from SmartScriptMgr.h; range checks skipped")
    if not data["reference_entries"]:
        warnings.append("reference_loot_template is empty; reference checks report every reference")
    warnings.append("C-10 map-bounds validation is skipped: map_dbc is empty in this database")

    return {
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "database": db.dsn["database"],
        "sourceVersion": source_version,
        "findings": [finding.as_dict() for finding in kept],
        "waived": [finding.as_dict() for finding, _ in waived],
        "staleWaivers": stale,
        "coverage": coverage(data, kept),
        "warnings": warnings,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Read-only content audit")
    parser.add_argument("--config", default="env/dist/etc/worldserver.conf",
                        help="worldserver config holding WorldDatabaseInfo")
    parser.add_argument("--waivers", default="tools/dev/content-audit-waivers.json")
    parser.add_argument("--json", default="", help="write the full report as JSON")
    parser.add_argument("--data-dir", default="",
                        help="client data directory holding dbc/Spell.dbc")
    parser.add_argument("--limit", type=int, default=500,
                        help="maximum findings in the Markdown table")
    args = parser.parse_args(argv)

    root = Path(__file__).resolve().parent.parent.parent
    try:
        result = run(Path(args.config), root, Path(args.waivers),
                     Path(args.data_dir) if args.data_dir else None)
    except AuditError as exc:
        print(f"content-audit: {exc}", file=sys.stderr)
        return 2

    print(render_markdown(result, args.limit), end="")
    if args.json:
        try:
            Path(args.json).write_text(json.dumps(result, indent=2) + "\n",
                                       encoding="utf-8")
        except OSError as exc:
            print(f"content-audit: cannot write {args.json}: {exc}", file=sys.stderr)
            return 2
    return 1 if any(f["severity"] == "blocker" for f in result["findings"]) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
