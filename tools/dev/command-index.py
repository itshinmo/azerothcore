#!/usr/bin/env python3
"""Generate the command index from src/server/scripts/Commands/cs_*.cpp.

Usage:
    python3 tools/dev/command-index.py            # write runbook/gm/command-index.md
    python3 tools/dev/command-index.py --check    # fail if the file is stale
"""

import argparse
import glob
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
COMMANDS_DIR = os.path.join(ROOT, "src", "server", "scripts", "Commands")
RBAC_HEADER = os.path.join(ROOT, "src", "server", "game", "Accounts", "RBAC.h")
OUTPUT = os.path.join(ROOT, "runbook", "gm", "command-index.md")

CONST_RE = re.compile(r"(RBAC_PERM_[A-Z0-9_]+)\s*=\s*(\d+)")


def load_constants():
    constants = {}
    with open(RBAC_HEADER, encoding="utf-8") as handle:
        for line in handle:
            match = CONST_RE.search(line)
            if match:
                constants[match.group(1)] = int(match.group(2))
    return constants


def extract_block(text, start):
    depth = 0
    in_string = False
    escaped = False
    for index in range(start, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise ValueError("unbalanced command table")


def split_fields(block):
    body = block[1:-1]
    fields = []
    current = ""
    depth = 0
    in_string = False
    escaped = False
    for char in body:
        if in_string:
            current += char
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
            current += char
        elif char in "{([":
            depth += 1
            current += char
        elif char in "})]":
            depth -= 1
            current += char
        elif char == "," and depth == 0:
            fields.append(current.strip())
            current = ""
        else:
            current += char
    if current.strip():
        fields.append(current.strip())
    return fields


def parse_tables():
    tables = {}
    files = sorted(glob.glob(os.path.join(COMMANDS_DIR, "cs_*.cpp")))
    for path in files:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        for match in re.finditer(r"static\s+ChatCommandTable\s+(\w+)\s*(?:=\s*)?(?=\{)", text):
            name = match.group(1)
            block = extract_block(text, text.index("{", match.end()))
            entries = []
            for item in split_fields(block):
                if not item.startswith("{"):
                    continue
                fields = split_fields(item)
                if not fields:
                    continue
                key_match = re.match(r'^"([^"]*)"', fields[0])
                if not key_match:
                    continue
                permission = None
                for field in fields:
                    perm_match = re.search(r"rbac::(RBAC_PERM_[A-Z0-9_]+)", field)
                    if perm_match:
                        permission = perm_match.group(1)
                target = fields[1].strip() if len(fields) > 1 else ""
                entries.append((key_match.group(1), target, permission))
            tables[(path, name)] = entries

        if "ChatCommandTable" in text and not any(table_path == path for (table_path, _) in tables):
            raise SystemExit(f"{os.path.basename(path)}: found ChatCommandTable declarations but parsed no tables")

    return tables, files


def build_mapping():
    tables, files = parse_tables()
    mapping = {}
    reachable = set()
    unresolved = []
    duplicates = []

    def walk(path, table, prefix, seen):
        marker = (path, table)
        if marker in seen:
            return
        reachable.add(marker)
        seen = seen | {marker}
        for key, target, permission in tables.get(marker, []):
            command = f"{prefix} {key}".strip() if key else prefix
            if (path, target) in tables:
                walk(path, target, command, seen)
            elif target.lower().endswith("commandtable"):
                unresolved.append(f"{os.path.basename(path)}: {prefix or '<root>'} -> {target}")
            elif permission:
                if command in mapping:
                    duplicates.append(command)
                    continue
                mapping[command] = (permission, os.path.basename(path))

    for path in files:
        file_tables = [name for (table_path, name) in tables if table_path == path]
        if not file_tables:
            continue
        if (path, "commandTable") not in tables:
            raise SystemExit(f"{os.path.basename(path)}: missing commandTable")
        walk(path, "commandTable", "", set())

    unreachable = [
        f"{os.path.basename(path)}: {name}"
        for (path, name) in tables
        if (path, name) not in reachable
    ]
    if unresolved:
        raise SystemExit("unresolved command tables:\n  " + "\n  ".join(unresolved))
    if duplicates:
        raise SystemExit("duplicate command paths:\n  " + "\n  ".join(sorted(duplicates)))
    if unreachable:
        raise SystemExit("unreachable command tables:\n  " + "\n  ".join(sorted(unreachable)))

    return mapping


# Curated list of commands that have no row in data/sql/base/db_world/command.sql.
# Update manually when adding or removing such a command.
CODE_ONLY = {
    "account info",
    "account flag add",
    "account flag list",
    "account flag remove",
    "group invites",
    "npc showloot",
    "pet rename",
    "rbac account deny",
    "rbac account grant",
    "rbac account list",
    "rbac account revoke",
    "reload spell_cone",
    "server set security",
}


def render(mapping, constants):
    missing = sorted({permission for permission, _ in mapping.values() if permission not in constants})
    if missing:
        raise SystemExit(f"unknown permission constants: {', '.join(missing)}")

    missing_code_only = sorted(CODE_ONLY - mapping.keys())
    if missing_code_only:
        raise SystemExit(f"code-only list is stale: {', '.join(missing_code_only)}")

    lines = [
        "# GM command index",
        "",
        "> Generated by `make command-index` from `src/server/scripts/Commands/cs_*.cpp`.",
        "> Do not edit by hand. In-game `.help <command>` remains authoritative for syntax.",
        "> Permission is the numeric RBAC id; constants live in `src/server/game/Accounts/RBAC.h`.",
        "> Curated code-only commands (no `command` table row):",
    ]

    code_only = [f"`.{command}`" for command in sorted(CODE_ONLY)]
    for index in range(0, len(code_only), 3):
        chunk = code_only[index:index + 3]
        suffix = "." if index + 3 >= len(code_only) else ","
        lines.append("> " + ", ".join(chunk) + suffix)

    lines.extend([
        "",
        "| Command | Permission | Source |",
        "|---------|------------|--------|",
    ])

    for command in sorted(mapping):
        permission, source = mapping[command]
        lines.append(f"| `.{command}` | {constants[permission]} | `{source}` |")

    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if the generated file is stale")
    args = parser.parse_args()

    constants = load_constants()
    mapping = build_mapping()
    content = render(mapping, constants)

    if args.check:
        try:
            with open(OUTPUT, encoding="utf-8") as handle:
                current = handle.read()
        except FileNotFoundError:
            current = ""
        if current != content:
            print(f"{OUTPUT} is stale; run `make command-index`.", file=sys.stderr)
            return 1
        print(f"command index: ok ({len(mapping)} commands)")
        return 0

    with open(OUTPUT, "w", encoding="utf-8") as handle:
        handle.write(content)
    print(f"wrote {OUTPUT} ({len(mapping)} commands)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
