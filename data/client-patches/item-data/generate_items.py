#!/usr/bin/env python3
"""Generate and validate ``items.json`` from the checked-in world-treasure inputs.

The world-treasures feature owns the item_template rows. This tool keeps the
client patch honest:

* ``item_template`` SQL supplies ID, name, class, subclass, SoundOverride,
  material, display, inventory and sheathe.
* The server ``item_dbc`` SQL is the mirror; every field must match.
* ``batch_01.csv`` is the authoring source; name, class, subclass, display and
  inventory are cross-checked there too.
* ``items.json`` must match all three. A mismatch fails the build.

Usage::

    python3 data/client-patches/item-data/generate_items.py --check
    python3 data/client-patches/item-data/generate_items.py --write
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def _first_existing(*paths: Path) -> Path:
    for path in paths:
        if path.is_file():
            return path
    return paths[-1]


# After the local-server-setup merge the canonical world-treasures files exist.
# Until then, the frozen snapshot under source/ is the checked-in input.
DEFAULT_BATCH_CSV = _first_existing(
    ROOT / "specs" / "world-treasures" / "batch_01.csv",
    HERE / "source" / "batch_01.csv",
)
DEFAULT_BATCH_SQL = _first_existing(
    ROOT / "data" / "sql" / "custom" / "db_world" / "world_treasures_batch_01.sql",
    HERE / "source" / "world_treasures_batch_01.sql",
)
DEFAULT_ITEM_DBC_SQL = _first_existing(
    ROOT / "data" / "sql" / "custom" / "db_world" / "world_treasures_item_dbc.sql",
    HERE / "source" / "world_treasures_item_dbc.sql",
)
DEFAULT_ITEMS = HERE / "items.json"

ITEM_FIELDS = (
    "id",
    "class",
    "subclass",
    "sound_override_subclass",
    "material",
    "display_info_id",
    "inventory_type",
    "sheathe_type",
)


class ItemsSourceError(ValueError):
    """The checked-in sources disagree with items.json."""


def _sql_tuples(text: str, table: str) -> tuple[list[str], list[list[str]]]:
    match = re.search(
        rf"REPLACE\s+INTO\s+`{re.escape(table)}`\s*\((.*?)\)\s*VALUES",
        text,
        re.IGNORECASE | re.DOTALL,
    )
    if not match:
        raise ItemsSourceError(f"{table}: cannot find REPLACE INTO ... VALUES")
    columns = [
        column.strip().strip("`") for column in match.group(1).split(",")
    ]
    body = text[match.end() :]
    rows: list[list[str]] = []
    index = 0
    length = len(body)
    while index < length:
        while index < length and body[index] in " \t\r\n,":
            index += 1
        if index >= length or body[index] == ";":
            break
        if body[index] != "(":
            raise ItemsSourceError(f"{table}: expected '(' at offset {index}")
        index += 1
        depth = 1
        fields: list[str] = []
        current: list[str] = []
        quoted = False
        while index < length and depth:
            char = body[index]
            if quoted:
                if char == "\\":
                    current.append(char)
                    index += 1
                    if index < length:
                        current.append(body[index])
                        index += 1
                    continue
                if char == "'":
                    quoted = False
                    current.append(char)
                    index += 1
                    continue
                current.append(char)
                index += 1
                continue
            if char == "'":
                quoted = True
                current.append(char)
                index += 1
                continue
            if char == "(":
                depth += 1
                current.append(char)
                index += 1
                continue
            if char == ")":
                depth -= 1
                if depth == 0:
                    fields.append("".join(current).strip())
                    index += 1
                    break
                current.append(char)
                index += 1
                continue
            if char == "," and depth == 1:
                fields.append("".join(current).strip())
                current = []
                index += 1
                continue
            current.append(char)
            index += 1
        if len(fields) != len(columns):
            raise ItemsSourceError(
                f"{table}: row has {len(fields)} values, expected {len(columns)}"
            )
        rows.append(fields)
    return columns, rows


def _unquote(value: str):
    value = value.strip()
    if value.upper() == "NULL":
        return None
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("\\'", "'").replace("\\\\", "\\")
    try:
        return int(value)
    except ValueError:
        try:
            return float(value)
        except ValueError as exc:
            raise ItemsSourceError(f"cannot parse SQL value: {value!r}") from exc


def parse_item_template_sql(path: Path = DEFAULT_BATCH_SQL) -> dict[int, dict]:
    text = Path(path).read_text(encoding="utf-8")
    columns, rows = _sql_tuples(text, "item_template")
    parsed = {}
    for values in rows:
        row = dict(zip(columns, (_unquote(value) for value in values)))
        item_id = int(row["entry"])
        parsed[item_id] = {
            "id": item_id,
            "name": row["name"],
            "class": int(row["class"]),
            "subclass": int(row["subclass"]),
            "sound_override_subclass": int(row["SoundOverrideSubclass"]),
            "material": int(row["Material"]),
            "display_info_id": int(row["displayid"]),
            "inventory_type": int(row["InventoryType"]),
            "sheathe_type": int(row["sheath"]),
        }
    return parsed


def parse_item_dbc_sql(path: Path = DEFAULT_ITEM_DBC_SQL) -> dict[int, dict]:
    text = Path(path).read_text(encoding="utf-8")
    columns, rows = _sql_tuples(text, "item_dbc")
    aliases = {
        "ClassID": "class",
        "SubclassID": "subclass",
        "Sound_Override_Subclassid": "sound_override_subclass",
        "Material": "material",
        "DisplayInfoID": "display_info_id",
        "InventoryType": "inventory_type",
        "SheatheType": "sheathe_type",
    }
    parsed = {}
    for values in rows:
        row = dict(zip(columns, (_unquote(value) for value in values)))
        item_id = int(row["ID"])
        parsed[item_id] = {
            "id": item_id,
            **{target: int(row[source]) for source, target in aliases.items()},
        }
    return parsed


def parse_batch_csv(path: Path = DEFAULT_BATCH_CSV) -> dict[int, dict]:
    parsed = {}
    with Path(path).open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            item_id = int(row["item_entry"])
            parsed[item_id] = {
                "id": item_id,
                "name": row["item_name"],
                "class": int(row["item_class"]),
                "subclass": int(row["item_subclass"]),
                "display_info_id": int(row["item_display_id"]),
                "inventory_type": int(row["inventory_type"]),
            }
    return parsed


def expected_items(
    batch_csv: Path = DEFAULT_BATCH_CSV,
    batch_sql: Path = DEFAULT_BATCH_SQL,
    item_dbc_sql: Path = DEFAULT_ITEM_DBC_SQL,
) -> dict[int, dict]:
    templates = parse_item_template_sql(batch_sql)
    mirrors = parse_item_dbc_sql(item_dbc_sql)
    csv_rows = parse_batch_csv(batch_csv)
    problems = []
    for item_id in sorted(set(templates) | set(mirrors) | set(csv_rows)):
        template = templates.get(item_id)
        mirror = mirrors.get(item_id)
        csv_row = csv_rows.get(item_id)
        if template is None:
            problems.append(f"{item_id}: missing from item_template SQL")
            continue
        if mirror is None:
            problems.append(f"{item_id}: missing from item_dbc SQL")
            continue
        if csv_row is None:
            problems.append(f"{item_id}: missing from batch CSV")
            continue
        for field in ITEM_FIELDS:
            if template[field] != mirror[field]:
                problems.append(
                    f"{item_id}: item_template {field}={template[field]!r} "
                    f"!= item_dbc {mirror[field]!r}"
                )
        for field in ("name", "class", "subclass", "display_info_id", "inventory_type"):
            if template[field] != csv_row[field]:
                problems.append(
                    f"{item_id}: item_template {field}={template[field]!r} "
                    f"!= CSV {csv_row[field]!r}"
                )
    if problems:
        raise ItemsSourceError("world-treasure sources disagree:\n" + "\n".join(problems))
    return {
        item_id: {
            "id": item_id,
            "name": templates[item_id]["name"],
            **{field: templates[item_id][field] for field in ITEM_FIELDS[1:]},
        }
        for item_id in sorted(templates)
    }


def validate_items(
    items_path: Path = DEFAULT_ITEMS,
    batch_csv: Path = DEFAULT_BATCH_CSV,
    batch_sql: Path = DEFAULT_BATCH_SQL,
    item_dbc_sql: Path = DEFAULT_ITEM_DBC_SQL,
) -> dict[int, dict]:
    expected = expected_items(batch_csv, batch_sql, item_dbc_sql)
    actual_list = json.loads(Path(items_path).read_text(encoding="utf-8"))
    actual = {int(row["id"]): row for row in actual_list}
    problems = []
    if len(actual) != len(actual_list):
        problems.append("items.json has duplicate IDs")
    for item_id in sorted(set(expected) | set(actual)):
        if item_id not in actual:
            problems.append(f"{item_id}: missing from items.json")
            continue
        if item_id not in expected:
            problems.append(f"{item_id}: unexpected in items.json")
            continue
        for field in ("name", *ITEM_FIELDS[1:]):
            if actual[item_id].get(field) != expected[item_id][field]:
                problems.append(
                    f"{item_id}: items.json {field}={actual[item_id].get(field)!r} "
                    f"!= source {expected[item_id][field]!r}"
                )
    if problems:
        raise ItemsSourceError("items.json disagrees with world-treasure sources:\n" + "\n".join(problems))
    return expected


def write_items(
    items_path: Path = DEFAULT_ITEMS,
    batch_csv: Path = DEFAULT_BATCH_CSV,
    batch_sql: Path = DEFAULT_BATCH_SQL,
    item_dbc_sql: Path = DEFAULT_ITEM_DBC_SQL,
) -> dict[int, dict]:
    expected = expected_items(batch_csv, batch_sql, item_dbc_sql)
    Path(items_path).write_text(
        json.dumps(list(expected.values()), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return expected


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--items", type=Path, default=DEFAULT_ITEMS)
    parser.add_argument("--batch-csv", type=Path, default=DEFAULT_BATCH_CSV)
    parser.add_argument("--batch-sql", type=Path, default=DEFAULT_BATCH_SQL)
    parser.add_argument("--item-dbc-sql", type=Path, default=DEFAULT_ITEM_DBC_SQL)
    parser.add_argument("--write", action="store_true", help="rewrite items.json from the sources")
    parser.add_argument("--check", action="store_true", help="validate items.json (default)")
    args = parser.parse_args(argv)
    try:
        if args.write:
            rows = write_items(args.items, args.batch_csv, args.batch_sql, args.item_dbc_sql)
            print(f"wrote {args.items}: {len(rows)} items")
        else:
            rows = validate_items(args.items, args.batch_csv, args.batch_sql, args.item_dbc_sql)
            print(f"{args.items}: {len(rows)} items match the world-treasure sources")
    except ItemsSourceError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
