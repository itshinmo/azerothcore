#!/usr/bin/env python3
"""Generate the GM Helper addon data manifest (one file, two tables).

Writes tools/gm-addon/GMHelperInstances.lua containing both:

  * GMHelperInstancesData — every dungeon and raid from DataDir/dbc/
    LFGDungeons.dbc (plus the vanilla sub-wings it omits) with entrance
    coordinates from acore_world.areatrigger_teleport.
  * GMHelperGearData — best equippable item per slot per class from
    acore_world.item_template (highest item level, class armor type and
    per-class weapon type filtered, top-2 rings and trinkets).

Both tables are written to the file the client provenably loads. Read-only
against the database; writes only the one manifest file.

Exit codes:
    0  manifest written
    2  configuration, database, or parse error
"""

from __future__ import annotations

import argparse
import importlib.util
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
_SPEC = importlib.util.spec_from_file_location("content_audit", HERE / "content-audit.py")
assert _SPEC and _SPEC.loader
audit = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = audit
_SPEC.loader.exec_module(audit)

DEFAULT_OUT = HERE.parent / "gm-addon" / "GMHelperInstances.lua"

EXPANSION_NAMES = {0: "Classic", 1: "The Burning Crusade", 2: "Wrath of the Lich King"}
KIND_NAMES = {1: "dungeon", 2: "raid"}  # TypeID 1/5 = dungeon (normal/heroic), 2 = raid

# Vanilla sub-areas with their own entrance that LFGDungeons.dbc does not list. Each
# points at one areatrigger_teleport row by id; levels are display-only.
EXTRA_ENTRIES = [
    {"name": "Scarlet Monastery - Library", "trigger": 614,
     "kind": "dungeon", "expansion": 0, "min_level": 29, "max_level": 35},
    {"name": "Scarlet Monastery - Armory", "trigger": 612,
     "kind": "dungeon", "expansion": 0, "min_level": 35, "max_level": 41},
    {"name": "Scarlet Monastery - Cathedral", "trigger": 610,
     "kind": "dungeon", "expansion": 0, "min_level": 39, "max_level": 45},
    {"name": "Maraudon - Purple Crystals", "trigger": 3134,
     "kind": "dungeon", "expansion": 0, "min_level": 42, "max_level": 48},
    {"name": "Dire Maul - West", "trigger": 3186,
     "kind": "dungeon", "expansion": 0, "min_level": 58, "max_level": 60},
    {"name": "Dire Maul - North", "trigger": 3189,
     "kind": "dungeon", "expansion": 0, "min_level": 57, "max_level": 63},
    {"name": "Stratholme - Service Entrance", "trigger": 2216,
     "kind": "dungeon", "expansion": 0, "min_level": 60, "max_level": 65},
]

# English class token from UnitClass -> (classId, armor subclasses for armor slots)
CLASSES = {
    "WARRIOR": (1, 4), "PALADIN": (2, 4), "HUNTER": (3, 3), "ROGUE": (4, 2),
    "PRIEST": (5, 1), "DEATHKNIGHT": (6, 4), "SHAMAN": (7, 3), "MAGE": (8, 1),
    "WARLOCK": (9, 1), "DRUID": (11, 2),
}

# Per class: main-hand/off-hand/ranged inventory types with the weapon
# subclasses the class can actually equip, plus relic flag and subclass.
# Note: this DB's relic subclass data is scrambled — libram 7 and idol 8 are
# right, but shaman totems and DK sigils both sit under subclass 9 (some
# sigils under 10), so their picks carry name guards.
WEAPON_MAP = {
    "WARRIOR": dict(mh=([13, 21, 17], [0, 1, 4, 5, 6, 7, 8, 13]),
                    oh=([14, 22], [6, 0, 4, 7, 13]),
                    ranged=([15, 25, 26], [2, 3, 16, 18]), relic=(False, [])),
    "PALADIN": dict(mh=([13, 21, 17], [0, 1, 4, 5, 6, 7, 8]),
                    oh=([14], [6]),
                    ranged=([], []), relic=(True, [7])),
    "HUNTER": dict(mh=([13, 21, 17], [0, 1, 6, 7, 10]),
                   oh=([], []),
                   ranged=([15, 26], [2, 3, 18]), relic=(False, [])),
    "ROGUE": dict(mh=([13, 21], [0, 4, 7, 11, 13, 15]),
                  oh=([22, 23], [14, 0, 4, 7, 11, 13, 15]),
                  ranged=([15, 25, 26], [2, 3, 16, 18]), relic=(False, [])),
    "PRIEST": dict(mh=([13, 21, 17], [4, 10, 15]),
                   oh=([23], [0]),
                   ranged=([15, 26], [19]), relic=(False, [])),
    "DEATHKNIGHT": dict(mh=([13, 21, 17], [0, 1, 4, 5, 6, 7, 8]),
                        oh=([22], [0, 1, 4, 7]),
                        ranged=([], []), relic=(True, [9])),
    "SHAMAN": dict(mh=([13, 21, 17], [0, 1, 4, 5, 10, 11, 13]),
                   oh=([14], [6]),
                   ranged=([], []), relic=(True, [9])),
    "MAGE": dict(mh=([13, 21, 17], [7, 10, 15]),
                 oh=([23], [0]),
                 ranged=([15, 26], [19]), relic=(False, [])),
    "WARLOCK": dict(mh=([13, 21, 17], [7, 10, 15]),
                    oh=([23], [0]),
                    ranged=([15, 26], [19]), relic=(False, [])),
    "DRUID": dict(mh=([13, 21, 17], [4, 5, 10, 13, 15]),
                  oh=([], []),
                  ranged=([], []), relic=(True, [8])),
}

# slot label -> InventoryType list for the fixed armor slots
ARMOR_SLOTS = [
    ("Head", [1]), ("Neck", [2]), ("Shoulder", [3]), ("Back", [16]),
    ("Chest", [5, 20]), ("Wrists", [9]), ("Hands", [10]), ("Waist", [6]),
    ("Legs", [7]), ("Feet", [8]),
]

ITEM_COLUMNS = ("entry, name, ItemLevel, Quality, maxcount")

# LFGDungeons.dbc 3.3.5a record layout (49 int fields):
# 0 id, 1..17 name locales, 18 name mask, 19 maxLevel, 20 minLevel, 21 targetLevel,
# 22 targetLevelMin, 23 mapId, 24 difficulty, 25 flags, 26 typeId, 27 faction,
# 28 texture, 29 expansionLevel, 30 orderIndex, 31 groupId, 32..47 description,
# 48 description mask.
FIELD_COUNT = 49
F_MAX_LEVEL = 19
F_MIN_LEVEL = 20
F_MAP = 23
F_TYPE = 26
F_EXPANSION = 29


class ManifestError(RuntimeError):
    """Configuration or parse failure. Maps to exit code 2."""


# ------------------------------------------------------------ LFGDungeons ---

def read_lfg_dungeons(path: Path) -> list[dict]:
    """Parse LFGDungeons.dbc (3.3.5a layout: 49 int fields, strings via offsets)."""
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise ManifestError(f"cannot read {path}: {exc}") from exc
    if len(data) < 20 or data[:4] != b"WDBC":
        raise ManifestError(f"{path} is not a WDBC file")
    record_count, field_count, record_size, string_block_size = struct.unpack_from(
        "<4I", data, 4)
    if field_count != FIELD_COUNT:
        raise ManifestError(f"{path} has {field_count} fields, expected {FIELD_COUNT}")
    records_size = record_count * record_size
    records = data[20:20 + records_size]
    string_block = data[20 + records_size:]
    if len(records) != records_size or len(string_block) != string_block_size:
        raise ManifestError(f"{path} is truncated")
    if record_size != FIELD_COUNT * 4:
        raise ManifestError(f"{path} record size {record_size}, expected {FIELD_COUNT * 4}")

    def string_at(offset: int) -> str:
        end = string_block.find(b"\x00", offset)
        if end < 0:
            end = len(string_block)
        return string_block[offset:end].decode("utf-8", "replace")

    rows: list[dict] = []
    for index in range(record_count):
        fields = struct.unpack_from(f"<{FIELD_COUNT}i", records, index * record_size)
        rows.append({
            "id": fields[0],
            "name": string_at(fields[1]),
            "min_level": fields[20],
            "max_level": fields[19],
            "map": fields[F_MAP],
            "difficulty": fields[24],
            "type": fields[F_TYPE],
            "expansion": fields[F_EXPANSION],
        })
    return rows


def collapse_by_map(rows: list[dict]) -> list[dict]:
    """One entry per (map, kind); name and levels from the lowest difficulty."""
    by_key: dict[tuple[int, str], list[dict]] = {}
    for row in rows:
        kind = KIND_NAMES.get(row["type"])
        if not kind:
            continue
        by_key.setdefault((row["map"], kind), []).append(row)
    entries = []
    for (map_id, kind), group in sorted(by_key.items()):
        picked = min(group, key=lambda r: (r["difficulty"], r["id"]))
        entries.append({
            "map": map_id,
            "expansion": picked["expansion"],
            "kind": kind,
            "name": picked["name"],
            "min_level": picked["min_level"],
            "max_level": picked["max_level"],
            "difficulty": picked["difficulty"],
        })
    return entries


def pick_trigger(triggers: list[dict]) -> dict | None:
    """Named entrance trigger first, then the lowest trigger id."""
    for trigger in triggers:
        if "entrance" in trigger["name"].lower():
            return trigger
    return triggers[0] if triggers else None


def entrance_triggers(db: audit.Db) -> tuple[dict[int, dict], dict[int, list], dict[int, dict]]:
    """Entrance triggers per target map from areatrigger_teleport.

    Returns the picked trigger per map, the raw trigger lists per map, and a
    trigger-id index. The raw lists back the multi-trigger ambiguity warning.
    """
    rows = db.query(
        "SELECT id, target_map, target_position_x, target_position_y, "
        "target_position_z, target_orientation, COALESCE(Name, '') "
        "FROM areatrigger_teleport ORDER BY id")
    by_map: dict[int, list[dict]] = {}
    by_id: dict[int, dict] = {}
    for (trigger_id, target_map, x, y, z, o, name) in rows:
        trigger = {
            "id": int(trigger_id), "map": int(target_map),
            "x": float(x), "y": float(y), "z": float(z), "o": float(o),
            "name": name,
        }
        by_map.setdefault(trigger["map"], []).append(trigger)
        by_id[trigger["id"]] = trigger
    picked = {map_id: pick_trigger(triggers) for map_id, triggers in by_map.items()}
    return picked, by_map, by_id


def instance_entries(conf: Path) -> list[dict]:
    """Instances table for the manifest (LFGDungeons + extras + coordinates)."""
    dsn = audit.parse_world_dsn(conf)
    data_dir = audit.parse_data_dir(conf)
    if not data_dir:
        raise ManifestError(f"DataDir not found in {conf}")
    dbc_path = data_dir / "dbc" / "LFGDungeons.dbc"

    entries = collapse_by_map(read_lfg_dungeons(dbc_path))
    triggers, triggers_by_map, triggers_by_id = entrance_triggers(audit.Db(dsn))

    seen = {entry["name"] for entry in entries}
    for entry in entries:
        entry["tele"] = triggers.get(entry["map"])
    for extra in EXTRA_ENTRIES:
        tele = triggers_by_id.get(extra["trigger"])
        if not tele:
            raise ManifestError(
                f"EXTRA_ENTRIES trigger {extra['trigger']} ({extra['name']}) not found "
                "in areatrigger_teleport")
        if extra["name"] in seen:
            raise ManifestError(
                f"EXTRA_ENTRIES {extra['name']} duplicates an LFG entry")
        seen.add(extra["name"])
        entries.append({
            "map": tele["map"],
            "expansion": extra["expansion"],
            "kind": extra["kind"],
            "name": extra["name"],
            "min_level": extra["min_level"],
            "max_level": extra["max_level"],
            "difficulty": 0,
            "tele": tele,
        })

    entries.sort(key=lambda entry: (entry["expansion"], entry["kind"], entry["name"]))

    missing: list[str] = []
    ambiguous: list[str] = []
    for entry in entries:
        tele = entry["tele"]
        if not tele:
            missing.append(entry["name"])
        elif len(triggers_by_map.get(entry["map"], [])) > 1 \
                and "entrance" not in tele["name"].lower():
            # Several triggers on the map and none named "entrance": the chosen row
            # may be a wing of a multi-wing instance rather than the main door.
            ambiguous.append(f'{entry["name"]} (map {entry["map"]}, trigger '
                             f'{tele["id"]} "{tele["name"]}")')
    for entry in entries:
        if not entry.get("tele"):
            entry["tele"] = None
    return entries, missing, ambiguous


def lua_escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"')


def render_instances(entries: list[dict]) -> list[str]:
    lines = ["GMHelperInstancesData = {"]
    for entry in entries:
        tele = entry.get("tele")
        tele_fields = ""
        if tele:
            tele_fields = (f', x = {tele["x"]:.4f}, y = {tele["y"]:.4f}, '
                           f'z = {tele["z"]:.4f}, o = {tele["o"]:.4f}')
        lines.append(
            f'  {{ name = "{lua_escape(entry["name"])}", map = {entry["map"]}, '
            f'expansion = {entry["expansion"]}, kind = "{entry["kind"]}", '
            f'minLevel = {entry["min_level"]}, maxLevel = {entry["max_level"]}'
            f'{tele_fields} }},')
    lines.append("}")
    return lines


# ------------------------------------------------------------------ gear ---

def top_items(db: audit.Db, where: str, limit: int) -> list[tuple]:
    return db.query(
        f"SELECT {ITEM_COLUMNS} FROM item_template WHERE {where} "
        f"ORDER BY ItemLevel DESC, Quality DESC, entry ASC LIMIT {limit}")


def grants_for_class(db: audit.Db, token: str) -> list[dict]:
    class_id, armor_subclass = CLASSES[token]
    spec = WEAPON_MAP[token]
    class_mask = 1 << (class_id - 1)
    base = (f"(AllowableClass = -1 OR (AllowableClass & {class_mask}) <> 0) "
            f"AND (AllowableRace = -1 OR (AllowableRace & 1) <> 0) "
            "AND RequiredSkill = 0 AND requiredspell = 0 AND class IN (2, 4) "
            "AND (FlagsExtra & 8192) = 0")

    grants: list[dict] = []
    for slot, inventory_types in ARMOR_SLOTS:
        # Cloaks are always subclass 1, whatever the wearer's armor class.
        subclasses = "1, 0" if slot == "Back" else f"{armor_subclass}, 0"
        types = ", ".join(str(t) for t in inventory_types)
        rows = top_items(db, base + f" AND InventoryType IN ({types}) "
                                    f"AND subclass IN ({subclasses})", 1)
        if rows:
            grants.append({"slot": slot, "id": int(rows[0][0]), "name": rows[0][1],
                           "ilvl": int(rows[0][2])})
        else:
            print(f"  WARNING: {token} {slot}: no item found", file=sys.stderr)

    for label, inventory_type, count in (
            ("Finger 1", 11, 2), ("Trinket 1", 12, 2)):
        rows = top_items(db, base + f" AND InventoryType = {inventory_type}", count)
        for index, row in enumerate(rows, 1):
            grants.append({"slot": f"{label.rsplit(' ', 1)[0]} {index}",
                           "id": int(row[0]), "name": row[1], "ilvl": int(row[2])})

    hands = [
        ("Main Hand", *spec["mh"]), ("Off Hand", *spec["oh"]),
        ("Ranged", *spec["ranged"]),
        ("Relic", [28], spec["relic"][1]) if spec["relic"][0] else ("Relic", [], []),
    ]
    for slot, inventory_types, subclasses in hands:
        if not inventory_types:
            continue
        types = ", ".join(str(t) for t in inventory_types)
        subs = ", ".join(str(s) for s in subclasses)
        # DB data bug: this fork's relic subclass data is scrambled — libram 7,
        # idol 8 are right, but DK sigils and shaman totems both sit under
        # subclass 9 (and some sigils under 10). Until a data fix splits them,
        # the RELIC pick guards by name in the direction each class needs.
        name_guard = ""
        if slot == "Relic" and token == "SHAMAN":
            subs = "9, 10"
            name_guard = " AND name NOT LIKE '%Sigil%'"
        elif slot == "Relic" and token == "DEATHKNIGHT":
            subs = "9, 10"
            name_guard = " AND name LIKE '%Sigil%'"
        rows = top_items(db, base + f" AND InventoryType IN ({types}) "
                                    f"AND subclass IN ({subs}){name_guard}", 1)
        if rows:
            grants.append({"slot": slot, "id": int(rows[0][0]), "name": rows[0][1],
                           "ilvl": int(rows[0][2])})
        else:
            print(f"  WARNING: {token} {slot}: no item found", file=sys.stderr)
    return grants


def gear_grants(conf: Path) -> dict[str, list[dict]]:
    db = audit.Db(audit.parse_world_dsn(conf))
    data = {token: grants_for_class(db, token) for token in CLASSES}
    short = {token: len(grants) for token, grants in data.items() if len(grants) < 12}
    if short:
        for token, count in short.items():
            print(f"  WARNING: {token} has only {count} grants", file=sys.stderr)
        print("error: refusing to write a manifest with incomplete classes", file=sys.stderr)
        raise ManifestError("incomplete class grants")
    return data


def render_gear(data: dict[str, list[dict]]) -> list[str]:
    lines = ["GMHelperGearData = {"]
    for token in data:
        lines.append(f'  {token} = {{')
        for grant in data[token]:
            lines.append(
                f'    {{ slot = "{lua_escape(grant["slot"])}", id = {grant["id"]}, '
                f'name = "{lua_escape(grant["name"])}", ilvl = {grant["ilvl"]} }},')
        lines.append("  },")
    lines.append("}")
    return lines


# ------------------------------------------------------------------ main ---

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--conf", type=Path,
                        default=HERE.parent.parent / "env/dist/etc/worldserver.conf",
                        help="worldserver.conf path for WorldDatabaseInfo and DataDir")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="manifest output path")
    args = parser.parse_args()

    entries, missing, ambiguous = instance_entries(args.conf)
    gear = gear_grants(args.conf)

    out_lines = [
        "-- Generated by tools/dev/gen-addon-manifest.py. Do not edit by hand;",
        "-- rerun the generator. Instances come from LFGDungeons.dbc plus the",
        "-- vanilla sub-wings it omits, entrance coordinates from",
        "-- areatrigger_teleport, gear picks from item_template.",
    ]
    out_lines += render_instances(entries)
    out_lines += render_gear(gear)
    text = "\n".join(out_lines) + "\n"
    args.out.write_text(text, encoding="utf-8")

    with_tele = sum(1 for entry in entries if entry["tele"])
    grants = sum(len(v) for v in gear.values())
    print(f"{args.out}: {len(entries)} instances ({with_tele} with coordinates), "
          f"{grants} gear grants across {len(gear)} classes")
    if missing:
        print(f"  WARNING: no entrance trigger for {len(missing)}:", file=sys.stderr)
        for name in missing:
            print(f"    {name}", file=sys.stderr)
    if ambiguous:
        print(f"  WARNING: ambiguous entrance among several triggers for {len(ambiguous)}:",
              file=sys.stderr)
        for name in ambiguous:
            print(f"    {name}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (audit.AuditError, ManifestError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(2)
