#!/usr/bin/env python3
"""Export world data artifacts for the public catalog.

Contract: specs/world-data.md. Read-only. Produces one JSON document per entity and one spawn
set per entity, plus a search index and meta.json.

Exit codes:
    0  export written
    2  configuration, database, or output error
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import shutil
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("content_audit", HERE / "content-audit.py")
assert SPEC and SPEC.loader
audit = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = audit
SPEC.loader.exec_module(audit)

SCHEMA_VERSION = 1
MAX_SPAWN_POINTS = 500
BUCKET_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"


class ExportError(RuntimeError):
    """Configuration, database, or output failure. Maps to exit code 2."""


def bucket_for(name: str) -> str:
    first = name.strip().lower()[:1]
    return first if first and first in BUCKET_CHARS else "_"


def world_time() -> str:
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, sort_keys=True,
                               separators=(",", ":")) + "\n", encoding="utf-8")


def parse_quest_objectives(row: list[str]) -> list[dict]:
    objectives = []
    for slot in range(4):
        target = int(row[6 + slot] or 0)
        count = int(row[10 + slot] or 0)
        if target == 0:
            continue
        objectives.append({
            "kind": "creature" if target > 0 else "gameobject",
            "id": abs(target),
            "count": count,
        })
    for slot in range(6):
        item = int(row[14 + slot] or 0)
        count = int(row[20 + slot] or 0)
        if item == 0:
            continue
        objectives.append({"kind": "item", "id": item, "count": count})
    return objectives


def load_entities(db: audit.Db) -> dict:
    entities: dict = {"npc": {}, "item": {}, "quest": {}, "object": {}, "spawns": {}}

    starters = {}
    for table, kind, template in (
            ("creature_queststarter", "creature", "creature_template"),
            ("gameobject_queststarter", "object", "gameobject_template")):
        sql = (f"SELECT s.id, s.quest, COALESCE(t.name, '') FROM {table} s "
               f"LEFT JOIN {template} t ON t.entry = s.id")
        for giver, quest, name in db.query(sql):
            starters.setdefault(int(quest), []).append(
                {"kind": kind, "id": int(giver), "name": name})
    enders = {}
    for table, kind, template in (
            ("creature_questender", "creature", "creature_template"),
            ("gameobject_questender", "object", "gameobject_template")):
        sql = (f"SELECT s.id, s.quest, COALESCE(t.name, '') FROM {table} s "
               f"LEFT JOIN {template} t ON t.entry = s.id")
        for giver, quest, name in db.query(sql):
            enders.setdefault(int(quest), []).append(
                {"kind": kind, "id": int(giver), "name": name})
    npc_starters = {ref["id"] for refs in starters.values() for ref in refs
                    if ref["kind"] == "creature"}
    npc_enders = {ref["id"] for refs in enders.values() for ref in refs
                  if ref["kind"] == "creature"}

    for row in db.query(
            "SELECT entry, name, subname, minlevel, maxlevel, `rank`, faction, npcflag, "
            "AIName, ScriptName FROM creature_template ORDER BY entry"):
        entry = int(row[0])
        flags = int(row[7] or 0)
        entities["npc"][entry] = {
            "id": entry, "name": row[1], "subname": row[2],
            "level": int(row[3] or 0), "maxLevel": int(row[4] or 0),
            "rank": int(row[5] or 0), "faction": int(row[6] or 0),
            "npcFlags": flags,
            "questStarter": entry in npc_starters,
            "questEnder": entry in npc_enders,
            "vendor": flags & 0x80 == 0x80,
            "trainer": flags & 0x10 == 0x10,
            "aiName": row[8], "scriptName": row[9],
        }

    for row in db.query(
            "SELECT entry, name, Quality, ItemLevel, RequiredLevel, class, subclass, "
            "displayid, SellPrice FROM item_template ORDER BY entry"):
        entry = int(row[0])
        entities["item"][entry] = {
            "id": entry, "name": row[1], "quality": int(row[2] or 0),
            "itemLevel": int(row[3] or 0), "requiredLevel": int(row[4] or 0),
            "class": int(row[5] or 0), "subclass": int(row[6] or 0),
            "displayId": int(row[7] or 0), "sellPrice": int(row[8] or 0),
        }

    quest_sql = """
        SELECT q.ID, q.QuestLevel, q.MinLevel, q.QuestSortID, q.QuestType, q.StartItem,
               q.RequiredNpcOrGo1, q.RequiredNpcOrGo2, q.RequiredNpcOrGo3, q.RequiredNpcOrGo4,
               q.RequiredNpcOrGoCount1, q.RequiredNpcOrGoCount2,
               q.RequiredNpcOrGoCount3, q.RequiredNpcOrGoCount4,
               q.RequiredItemId1, q.RequiredItemId2, q.RequiredItemId3,
               q.RequiredItemId4, q.RequiredItemId5, q.RequiredItemId6,
               q.RequiredItemCount1, q.RequiredItemCount2, q.RequiredItemCount3,
               q.RequiredItemCount4, q.RequiredItemCount5, q.RequiredItemCount6,
               a.PrevQuestID, a.NextQuestID, q.LogTitle
        FROM quest_template q
        LEFT JOIN quest_template_addon a ON a.ID = q.ID
        ORDER BY q.ID
    """
    for row in db.query(quest_sql):
        quest_id = int(row[0])
        sort_id = int(row[3] or 0)
        entities["quest"][quest_id] = {
            "id": quest_id, "title": row[28],
            "level": int(row[1] or 0), "minLevel": int(row[2] or 0),
            "zone": sort_id if sort_id > 0 else 0,
            "sortCategory": sort_id if sort_id < 0 else 0,
            "type": int(row[4] or 0),
            "startItem": int(row[5] or 0),
            "objectives": parse_quest_objectives(row),
            "starters": sorted(starters.get(quest_id, []),
                               key=lambda ref: (ref["kind"], ref["id"])),
            "enders": sorted(enders.get(quest_id, []),
                             key=lambda ref: (ref["kind"], ref["id"])),
            "prerequisites": {
                "previous": int(row[26] or 0),
                "next": int(row[27] or 0),
            },
        }

    for row in db.query(
            "SELECT entry, name, type, AIName, ScriptName FROM gameobject_template "
            "ORDER BY entry"):
        entry = int(row[0])
        entities["object"][entry] = {
            "id": entry, "name": row[1], "type": int(row[2] or 0),
            "aiName": row[3], "scriptName": row[4],
        }

    spawn_sql = {
        "npc": ("SELECT id, map, position_x, position_y, position_z, orientation, "
                "spawntimesecs, guid FROM creature ORDER BY id, map, guid", "npc"),
        "object": ("SELECT id, map, position_x, position_y, position_z, orientation, "
                   "spawntimesecs, guid FROM gameobject ORDER BY id, map, guid", "object"),
    }
    for kind, (sql, entity_kind) in spawn_sql.items():
        sets: dict[int, list[dict]] = {}
        for row in db.query(sql):
            entry, map_id = int(row[0]), int(row[1])
            sets.setdefault(entry, []).append({
                "map": map_id,
                "x": round(float(row[2]), 4),
                "y": round(float(row[3]), 4),
                "z": round(float(row[4]), 4),
                "orientation": round(float(row[5]), 4),
                "respawnSeconds": int(row[6] or 0),
                "spawnId": int(row[7]),
            })
        entities["spawns"][kind] = sets
    return entities


def write_spawns(root: Path, kind: str, entry: int, points: list[dict], stamp: str) -> list[str]:
    envelope = {"entry": entry, "kind": kind, "schemaVersion": SCHEMA_VERSION,
                "generatedAt": stamp}
    target = root / "spawns" / kind / f"{entry}.json"
    if len(points) <= MAX_SPAWN_POINTS:
        write_json(target, dict(envelope, points=points))
        return []
    parts = []
    by_map: dict[int, list[dict]] = {}
    for point in points:
        by_map.setdefault(point["map"], []).append(point)
    for map_id in sorted(by_map):
        part = root / "spawns" / kind / f"{entry}-{map_id}.json"
        write_json(part, dict(envelope, map=map_id, points=by_map[map_id]))
        parts.append(str(part.relative_to(root)))
    write_json(target, dict(envelope, parts=parts))
    return parts


def prepare_output(output: Path, force: bool) -> Path:
    """Validate the target and return an empty temporary directory next to it."""
    temp = output.with_name(output.name + ".tmp")
    if temp.exists():
        shutil.rmtree(temp)
    if output.exists() and any(output.iterdir()):
        if not force:
            raise ExportError(f"{output} is not empty; pass --force to replace it")
        meta = output / "meta.json"
        if not meta.exists():
            raise ExportError(f"refusing to replace {output}: no meta.json, "
                              "not an export directory")
        try:
            payload = json.loads(meta.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise ExportError(f"refusing to replace {output}: unreadable meta.json: {exc}") from exc
        if payload.get("schemaVersion") != SCHEMA_VERSION:
            raise ExportError(f"refusing to replace {output}: meta.json has schemaVersion "
                              f"{payload.get('schemaVersion')!r}, expected {SCHEMA_VERSION}")
    temp.mkdir(parents=True)
    return temp


def commit_output(output: Path, temp: Path) -> None:
    """Swap the finished temporary directory into place."""
    if output.exists():
        old = output.with_name(output.name + ".old")
        if old.exists():
            shutil.rmtree(old)
        output.rename(old)
        temp.rename(output)
        shutil.rmtree(old)
    else:
        temp.rename(output)


def export(config: Path, output: Path, force: bool) -> dict:
    started = time.monotonic()
    dsn = audit.parse_world_dsn(config)
    db = audit.Db(dsn)
    entities = load_entities(db)
    version = db.query("SELECT db_version FROM version LIMIT 1")
    source_version = version[0][0] if version else "unknown"
    stamp = world_time()
    temp = prepare_output(output, force)

    search: dict[str, list[dict]] = {}
    counts = {"npc": 0, "item": 0, "quest": 0, "object": 0, "spell": 0,
              "spawns": 0, "parts": 0}
    for kind in ("npc", "item", "quest", "object"):
        for entry, document in entities[kind].items():
            write_json(temp / kind / f"{entry}.json",
                       dict(document, schemaVersion=SCHEMA_VERSION, generatedAt=stamp))
            name = document.get("name") or document.get("title") or ""
            search.setdefault(bucket_for(name), []).append(
                {"type": kind, "id": entry, "name": name})
            counts[kind] += 1
    for kind in ("npc", "object"):
        for entry, points in entities["spawns"][kind].items():
            counts["parts"] += len(write_spawns(temp, kind, entry, points, stamp))
            counts["spawns"] += 1

    for bucket, rows in search.items():
        rows.sort(key=lambda row: (row["type"], row["id"]))
        write_json(temp / "search" / f"{bucket}.json",
                   {"bucket": bucket, "schemaVersion": SCHEMA_VERSION,
                    "generatedAt": stamp, "results": rows})

    meta = {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": stamp,
        "sourceDatabase": dsn["database"],
        "sourceDatabaseVersion": source_version,
        "counts": counts,
        "buckets": len(search),
        "durationSeconds": round(time.monotonic() - started, 2),
    }
    write_json(temp / "meta.json", meta)
    commit_output(output, temp)
    return meta


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Export world data artifacts")
    parser.add_argument("--config", default="env/dist/etc/worldserver.conf")
    parser.add_argument("--output", default="env/export")
    parser.add_argument("--force", action="store_true",
                        help="replace a non-empty output directory")
    args = parser.parse_args(argv)

    try:
        meta = export(Path(args.config), Path(args.output), args.force)
    except (audit.AuditError, ExportError, OSError) as exc:
        print(f"world-export: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(meta, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
