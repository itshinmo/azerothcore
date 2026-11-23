#!/usr/bin/env python3
"""Check the objective task seed against the launch pools.

Every faction must see at least five daily tasks in the 1-9 band and at least seven in the 15-30 and
31-80 bands, with at least two distinct focus zones per faction. Run from the repository root:

    python3 modules/mod-objectives/tools/check_task_data.py
"""

import re
import sys
from pathlib import Path

SQL = Path("data/sql/custom/db_world/objectives_engine.sql")
BANDS = ((1, 9, 5), (15, 30, 7), (31, 80, 7))


def load_tasks():
    text = SQL.read_text(encoding="utf-8")
    start = text.index("INSERT INTO `mod_objectives_task`")
    end = text.index(";", start)
    tasks = []
    for line in text[start:end].splitlines():
        match = re.match(r"\s*\((\d+),\s*'([^']*)',\s*(.*?)\),?\s*$", line)
        if not match:
            continue
        task_id = int(match.group(1))
        name = match.group(2)
        values = [int(value.strip()) for value in match.group(3).split(",")]
        if len(values) != 14:
            raise ValueError(f"task {task_id}: expected 14 numeric fields, got {len(values)}")
        (
            task_type,
            scope,
            _era,
            min_level,
            max_level,
            faction,
            zone_id,
            _target,
            _required,
            _marks,
            _coins,
            _commendations,
            _weight,
            _enabled,
        ) = values
        tasks.append(
            {
                "id": task_id,
                "name": name,
                "type": task_type,
                "scope": scope,
                "min": min_level,
                "max": max_level,
                "faction": faction,
                "zone": zone_id,
            }
        )
    return tasks


def eligible(task, faction, low, high):
    if task["scope"] != 1:
        return False
    if task["faction"] not in (0, faction):
        return False
    return task["min"] <= high and (task["max"] == 0 or task["max"] >= low)


def main():
    tasks = load_tasks()
    ids = {task["id"] for task in tasks}
    if len(ids) != len(tasks):
        print("FAIL: duplicate task ids")
        return 1

    failed = False
    for faction, label in ((1, "Alliance"), (2, "Horde")):
        for low, high, minimum in BANDS:
            pool = [task for task in tasks if eligible(task, faction, low, high)]
            zones = {task["zone"] for task in pool if task["zone"]}
            print(f"{label} {low}-{high}: {len(pool)} daily tasks, {len(zones)} focus zones")
            if len(pool) < minimum:
                print(f"FAIL: {label} {low}-{high} has {len(pool)} daily tasks, need {minimum}")
                failed = True
            if len(zones) < 2:
                print(f"FAIL: {label} {low}-{high} has fewer than two focus zones")
                failed = True

    print(f"loaded {len(tasks)} tasks")
    if failed:
        return 1
    print("PASS: task pools cover both factions and both level bands")
    return 0


if __name__ == "__main__":
    sys.exit(main())
