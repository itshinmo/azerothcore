#!/usr/bin/env python3
"""3.3.5a Item.dbc editor and patch-X builder.

The client resolves an item icon and inventory metadata from ``Item.dbc``. A
server-only custom item ID without a row shows the red question mark. This tool
extracts the highest-priority ``DBFilesClient\\Item.dbc`` below the project
item patch, upserts custom rows, sorts by ID, and packs ``patch-X.MPQ`` with
only that DBC.

3.3.5a ``Item.dbc`` is 8 fields per row (32 bytes):

    ID, Class, SubClass, SoundOverrideSubclass, Material, DisplayInfoID,
    InventoryType, SheatheType

Usage::

    python3 tools/client-patch/item_dbc.py inspect --dbc Item.dbc --ids 901001-901020
    python3 tools/client-patch/item_dbc.py edit --dbc Item.dbc --items items.json --out Item.dbc.new
    python3 tools/client-patch/item_dbc.py build --client ~/Games/wotlk-clean \\
        --items data/client-patches/item-data/items.json \\
        --out data/client-patches/item-data/dist/patch-X.MPQ \\
        --manifest data/client-patches/item-data/manifest.json \\
        --server-dbc ~/wow/Data/dbc/Item.dbc

``--server-dbc`` is optional; when given, server-only IDs or row conflicts abort the build.

No other DBC is read for writing. The display-ID check opens
``ItemDisplayInfo.dbc`` read-only and fails when a custom row points at a
missing display, which is the exact failure that produces the red question mark.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import struct
import sys
from dataclasses import dataclass
from pathlib import Path

import mpq

ITEM_DBC_PATH = "DBFilesClient\\Item.dbc"
ITEM_DISPLAY_DBC_PATH = "DBFilesClient\\ItemDisplayInfo.dbc"

FIELDS = 8
RECORD_SIZE = 32
HEADER_SIZE = 20
PROJECT_ITEM_ARCHIVE = "patch-x.mpq"
PROJECT_PATCHES = {"patch-x.mpq", "patch-y.mpq", "patch-z.mpq"}
FIXED_MTIME = datetime.datetime(2026, 11, 23, tzinfo=datetime.timezone.utc).timestamp()


class ItemDbcError(ValueError):
    """Invalid Item.dbc data or item row."""


def _signed(value: int) -> int:
    return value - 0x100000000 if value >= 0x80000000 else value


def _unsigned(value: int, field: str) -> int:
    if not -0x80000000 <= value <= 0xFFFFFFFF:
        raise ItemDbcError(f"{field} out of 32-bit range: {value}")
    return value & 0xFFFFFFFF


@dataclass(frozen=True)
class ItemRow:
    id: int
    item_class: int
    subclass: int
    sound_override_subclass: int
    material: int
    display_info_id: int
    inventory_type: int
    sheathe_type: int

    @classmethod
    def from_values(cls, values: list[int]) -> "ItemRow":
        if len(values) != FIELDS:
            raise ItemDbcError(f"Item.dbc row has {len(values)} fields, expected {FIELDS}")
        return cls(
            id=int(values[0]),
            item_class=int(values[1]),
            subclass=int(values[2]),
            sound_override_subclass=_signed(int(values[3])),
            material=int(values[4]),
            display_info_id=int(values[5]),
            inventory_type=int(values[6]),
            sheathe_type=int(values[7]),
        )

    @classmethod
    def from_dict(cls, data: dict) -> "ItemRow":
        def pick(*names, default=None):
            for name in names:
                if name in data:
                    return data[name]
            if default is not None:
                return default
            raise ItemDbcError(f"item row missing field: {'/'.join(names)}")

        try:
            return cls(
                id=int(pick("id", "entry", "ID")),
                item_class=int(pick("class", "item_class", "Class")),
                subclass=int(pick("subclass", "sub_class", "SubClass")),
                sound_override_subclass=int(
                    pick("sound_override_subclass", "SoundOverrideSubclass", default=-1)
                ),
                material=int(pick("material", "Material")),
                display_info_id=int(pick("display_info_id", "displayid", "DisplayInfoID")),
                inventory_type=int(pick("inventory_type", "InventoryType")),
                sheathe_type=int(pick("sheathe_type", "sheath", "SheatheType")),
            )
        except (TypeError, ValueError) as exc:
            raise ItemDbcError(f"invalid item row {data!r}: {exc}") from exc

    def to_values(self) -> list[int]:
        values = [
            self.id,
            self.item_class,
            self.subclass,
            self.sound_override_subclass,
            self.material,
            self.display_info_id,
            self.inventory_type,
            self.sheathe_type,
        ]
        for name, value in zip(
            (
                "ID",
                "Class",
                "SubClass",
                "SoundOverrideSubclass",
                "Material",
                "DisplayInfoID",
                "InventoryType",
                "SheatheType",
            ),
            values,
        ):
            _unsigned(value, name)
        return [value & 0xFFFFFFFF for value in values]

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "class": self.item_class,
            "subclass": self.subclass,
            "sound_override_subclass": self.sound_override_subclass,
            "material": self.material,
            "display_info_id": self.display_info_id,
            "inventory_type": self.inventory_type,
            "sheathe_type": self.sheathe_type,
        }

    def validate(self) -> None:
        if self.id <= 0:
            raise ItemDbcError(f"item ID must be positive: {self.id}")
        if self.item_class < 0 or self.subclass < 0:
            raise ItemDbcError(f"item {self.id}: negative class or subclass")
        if self.display_info_id < 0:
            raise ItemDbcError(f"item {self.id}: negative display info ID")
        if self.material < 0:
            raise ItemDbcError(f"item {self.id}: negative material")
        if self.inventory_type < 0:
            raise ItemDbcError(f"item {self.id}: negative inventory type")
        if self.sheathe_type < 0:
            raise ItemDbcError(f"item {self.id}: negative sheathe type")
        if self.sound_override_subclass < -1:
            raise ItemDbcError(f"item {self.id}: invalid SoundOverrideSubclass")
        _unsigned(self.id, "ID")
        _unsigned(self.item_class, "Class")
        _unsigned(self.subclass, "SubClass")
        _unsigned(self.material, "Material")
        _unsigned(self.display_info_id, "DisplayInfoID")
        _unsigned(self.inventory_type, "InventoryType")
        _unsigned(self.sheathe_type, "SheatheType")


@dataclass
class ItemDbc:
    rows: dict[int, ItemRow]
    strings: bytes = b"\0"

    @classmethod
    def from_bytes(cls, data: bytes) -> "ItemDbc":
        if len(data) < HEADER_SIZE:
            raise ItemDbcError("Item.dbc is shorter than the 20-byte header")
        magic, count, fields, record_size, string_size = struct.unpack_from("<4s4I", data, 0)
        if magic != b"WDBC":
            raise ItemDbcError(f"Item.dbc magic is {magic!r}, expected b'WDBC'")
        if fields != FIELDS:
            raise ItemDbcError(f"Item.dbc has {fields} fields, expected {FIELDS}")
        if record_size != RECORD_SIZE:
            raise ItemDbcError(f"Item.dbc row size is {record_size}, expected {RECORD_SIZE}")
        expected = HEADER_SIZE + count * record_size + string_size
        if len(data) != expected:
            raise ItemDbcError(
                f"Item.dbc length is {len(data)}, header says {expected} "
                f"({count} rows, {string_size} string bytes)"
            )
        rows: dict[int, ItemRow] = {}
        for index in range(count):
            offset = HEADER_SIZE + index * record_size
            values = list(struct.unpack_from("<8I", data, offset))
            row = ItemRow.from_values(values)
            row.validate()
            if row.id in rows:
                raise ItemDbcError(f"duplicate item ID in Item.dbc: {row.id}")
            rows[row.id] = row
        strings = data[HEADER_SIZE + count * record_size : expected]
        if not strings:
            strings = b"\0"
        return cls(rows, strings)

    def to_bytes(self) -> bytes:
        rows = sorted(self.rows.values(), key=lambda row: row.id)
        strings = self.strings if self.strings else b"\0"
        output = bytearray(
            struct.pack("<4s4I", b"WDBC", len(rows), FIELDS, RECORD_SIZE, len(strings))
        )
        for row in rows:
            row.validate()
            output += struct.pack("<8I", *row.to_values())
        output += strings
        return bytes(output)

    def upsert(self, items: list[ItemRow]) -> tuple[list[int], list[int]]:
        added: list[int] = []
        updated: list[int] = []
        for item in items:
            item.validate()
            if item.id in self.rows:
                updated.append(item.id)
            else:
                added.append(item.id)
            self.rows[item.id] = item
        return sorted(added), sorted(updated)

    def get(self, item_id: int) -> ItemRow | None:
        return self.rows.get(item_id)

    def validate(self) -> None:
        for row in self.rows.values():
            row.validate()

    def summary(self) -> dict:
        rows = sorted(self.rows.values(), key=lambda row: row.id)
        return {
            "fields": FIELDS,
            "record_size": RECORD_SIZE,
            "string_size": len(self.strings),
            "rows": len(rows),
            "min_id": rows[0].id if rows else None,
            "max_id": rows[-1].id if rows else None,
            "sorted": all(rows[index].id < rows[index + 1].id for index in range(len(rows) - 1)),
        }


def load_items(path: str | Path) -> list[ItemRow]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if isinstance(data, dict):
        data = data.get("items", [])
    if not isinstance(data, list) or not data:
        raise ItemDbcError(f"{path}: expected a non-empty JSON array of item rows")
    items = [ItemRow.from_dict(entry) for entry in data]
    seen = set()
    for item in items:
        if item.id in seen:
            raise ItemDbcError(f"{path}: duplicate item ID {item.id}")
        seen.add(item.id)
    return items


def extract_item_dbc(client: str | Path) -> tuple[Path, bytes]:
    data_dir = Path(client).expanduser() / "Data"
    result = mpq.find_highest(data_dir, ITEM_DBC_PATH, locale="enUS", order="english")
    if not result.winner:
        raise ItemDbcError(f"cannot find {ITEM_DBC_PATH} in {data_dir}")
    candidates = [path for path in result.sources if path.name.lower() not in PROJECT_PATCHES]
    if not candidates:
        raise ItemDbcError(
            f"{ITEM_DBC_PATH} only exists in a project patch; use a clean client bundle"
        )
    higher = [
        path
        for path in result.sources
        if path.name.lower() in PROJECT_PATCHES and path.name.lower() != PROJECT_ITEM_ARCHIVE
    ]
    if higher:
        raise ItemDbcError(
            "Item.dbc is also in a higher project patch "
            f"({', '.join(path.name for path in higher)}); X would not win"
        )
    source = candidates[-1]
    with mpq.Archive(source) as archive:
        data = archive.read_file(ITEM_DBC_PATH)
    return source, data


def parse_item_display_ids(data: bytes) -> set[int]:
    if len(data) < HEADER_SIZE:
        raise ItemDbcError(f"{ITEM_DISPLAY_DBC_PATH}: shorter than the 20-byte header")
    magic, count, fields, record_size, string_size = struct.unpack_from("<4s4I", data, 0)
    if magic != b"WDBC":
        raise ItemDbcError(f"{ITEM_DISPLAY_DBC_PATH}: magic is {magic!r}")
    if record_size < 4:
        raise ItemDbcError(f"{ITEM_DISPLAY_DBC_PATH}: row size is {record_size}")
    expected = HEADER_SIZE + count * record_size + string_size
    if len(data) < expected:
        raise ItemDbcError(
            f"{ITEM_DISPLAY_DBC_PATH}: length {len(data)} is shorter than header {expected}"
        )
    return {
        struct.unpack_from("<I", data, HEADER_SIZE + index * record_size)[0]
        for index in range(count)
    }


def item_display_ids(client: str | Path) -> set[int]:
    data_dir = Path(client).expanduser() / "Data"
    result = mpq.find_highest(data_dir, ITEM_DISPLAY_DBC_PATH, locale="enUS", order="english")
    if not result.winner:
        raise ItemDbcError(
            f"cannot find {ITEM_DISPLAY_DBC_PATH} in {data_dir}; "
            "pass --no-display-check only for offline fixtures"
        )
    candidates = [path for path in result.sources if path.name.lower() not in PROJECT_PATCHES]
    if not candidates:
        raise ItemDbcError(
            f"{ITEM_DISPLAY_DBC_PATH} only exists in a project patch; use a clean client"
        )
    with mpq.Archive(candidates[-1]) as archive:
        data = archive.read_file(ITEM_DISPLAY_DBC_PATH)
    return parse_item_display_ids(data)


def build_patch(
    source_dbc: str | Path,
    items_path: str | Path,
    out: str | Path,
    manifest_path: str | Path,
    *,
    source_label: str,
    source_sha256: str | None = None,
    displays: set[int] | None = None,
    server_dbc: str | Path | None = None,
    built_at: str | None = None,
) -> dict:
    source_path = Path(source_dbc)
    source_bytes = source_path.read_bytes()
    source_sha256 = source_sha256 or mpq.sha256_bytes(source_bytes)
    dbc = ItemDbc.from_bytes(source_bytes)
    before = len(dbc.rows)
    items = load_items(items_path)
    if displays is not None:
        missing = sorted(
            item.id for item in items if item.display_info_id not in displays
        )
        if missing:
            raise ItemDbcError(
                "custom items point at missing ItemDisplayInfo.dbc IDs: "
                + ", ".join(str(item_id) for item_id in missing)
            )
    added, updated = dbc.upsert(items)
    dbc.validate()

    server_input = None
    if server_dbc:
        server_path = Path(server_dbc).expanduser()
        server_bytes = server_path.read_bytes()
        server = ItemDbc.from_bytes(server_bytes)
        server_only = sorted(set(server.rows) - set(dbc.rows))
        conflicts = sorted(
            item_id
            for item_id in set(server.rows) & set(dbc.rows)
            if server.rows[item_id] != dbc.rows[item_id]
        )
        if server_only:
            raise ItemDbcError(
                "server Item.dbc has IDs not in the client union: "
                + ", ".join(str(item_id) for item_id in server_only)
                + "; merge them into items.json or use item_dbc rows instead of replacing the file"
            )
        if conflicts:
            raise ItemDbcError(
                "server Item.dbc disagrees with the client union for IDs: "
                + ", ".join(str(item_id) for item_id in conflicts)
            )
        server_input = {
            "sha256": mpq.sha256_bytes(server_bytes),
            "size": len(server_bytes),
            "rows": len(server.rows),
            "server_only_ids": [],
            "conflict_ids": [],
        }

    output_bytes = dbc.to_bytes()

    # Verify the bytes before packing, not only the object we edited.
    reparsed = ItemDbc.from_bytes(output_bytes)
    if len(reparsed.rows) != before + len(added):
        raise ItemDbcError("row count changed unexpectedly after write")
    for item in items:
        if reparsed.rows.get(item.id) != item:
            raise ItemDbcError(f"row {item.id} did not round-trip")

    out_path = Path(out).expanduser()
    manifest_file = Path(manifest_path).expanduser()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    build_dir = Path(manifest_path).expanduser().parent / "build"
    build_dir.mkdir(parents=True, exist_ok=True)
    dbc_file = build_dir / "Item.dbc"
    dbc_file.write_bytes(output_bytes)
    os.utime(dbc_file, (FIXED_MTIME, FIXED_MTIME))
    # The server loads the same DBC from DataDir/dbc/Item.dbc. Publish a matching
    # copy next to the MPQ so the owner can deploy both from one artifact set.
    server_copy = out_path.parent / "Item.dbc"
    server_copy.write_bytes(output_bytes)

    if out_path.exists():
        out_path.unlink()
    with mpq.Archive.create(out_path, max_files=8) as archive:
        archive.add_file(dbc_file, ITEM_DBC_PATH)

    with mpq.Archive(out_path) as archive:
        entries = archive.list_files(include_internal=True)
        names = {entry.name.lower() for entry in entries}
        if names != {ITEM_DBC_PATH.lower(), "(listfile)", "(attributes)"}:
            raise ItemDbcError(f"patch-X must contain only Item.dbc, found {sorted(names)}")
        if archive.read_file(ITEM_DBC_PATH) != output_bytes:
            raise ItemDbcError("packed Item.dbc differs from the edited DBC")
        verify = archive.verify_file(ITEM_DBC_PATH)
        if not verify.ok:
            raise ItemDbcError(f"packed Item.dbc failed StormLib verify: {verify.flags:#x}")
        info = archive.inspect()

    manifest = {
        "schema": 1,
        "archive": out_path.name,
        "sha256": info["sha256"],
        "size": info["size"],
        "format": info["format"],
        "compression": "zlib",
        "built_at": built_at
        or datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "dbc_files": 1,
        "items_sha256": mpq.sha256_file(items_path),
        "server_dbc": {
            "path": str(server_copy.relative_to(Path(manifest_path).expanduser().parent))
            if server_copy.is_relative_to(Path(manifest_path).expanduser().parent)
            else server_copy.name,
            "sha256": mpq.sha256_bytes(output_bytes),
            "rows": len(dbc.rows),
        },
        "server_dbc_input": server_input,
        "load_order": {
            "client": "3.3.5a enUS",
            "locale": "enUS",
            "order": "english",
            "project_family": ["patch-X.MPQ", "patch-Y.MPQ", "patch-Z.MPQ"],
            "expected_winner_for_item_dbc": "Data/patch-X.MPQ",
            "only_item_dbc_carrier": "patch-X.MPQ",
            "rationale": (
                "X, Y and Z each load after Reforged patch-U. Only X carries "
                "DBFilesClient\\Item.dbc, so X wins it without replacing another "
                "project DBC; Z remains the highest-priority map/UI archive."
            ),
            "source_archive": source_label,
            "source_sha256": source_sha256,
        },
        "dbc": [
            {
                "path": ITEM_DBC_PATH,
                "source_archive": source_label,
                "source_sha256": source_sha256,
                "output_sha256": mpq.sha256_bytes(output_bytes),
                "fields": FIELDS,
                "record_size": RECORD_SIZE,
                "rows_before": before,
                "rows_after": len(dbc.rows),
                "added_ids": added,
                "updated_ids": updated,
                "display_check": displays is not None,
            }
        ],
        "items": [item.to_dict() for item in sorted(items, key=lambda item: item.id)],
        "entries": [],
    }
    with mpq.Archive(out_path) as archive:
        manifest["entries"] = [
            {
                "path": entry.name,
                "size": entry.size,
                "compressed_size": entry.compressed_size,
                "sha256": archive.sha256(entry.name),
                "verify_flags": archive.verify_file(entry.name).flags,
            }
            for entry in sorted(archive.list_files(), key=lambda entry: entry.name.lower())
        ]
    manifest_file.parent.mkdir(parents=True, exist_ok=True)
    manifest_file.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return manifest


def build_from_client(
    client: str | Path,
    items_path: str | Path,
    out: str | Path,
    manifest_path: str | Path,
    *,
    check_displays: bool = True,
    server_dbc: str | Path | None = None,
) -> dict:
    source_archive, source_bytes = extract_item_dbc(client)
    build_dir = Path(manifest_path).expanduser().parent / "build"
    build_dir.mkdir(parents=True, exist_ok=True)
    source_file = build_dir / "Item.source.dbc"
    source_file.write_bytes(source_bytes)
    try:
        source_label = source_archive.resolve().relative_to(Path(client).expanduser().resolve()).as_posix()
    except ValueError:
        source_label = source_archive.name
    displays = item_display_ids(client) if check_displays else None
    return build_patch(
        source_file,
        items_path,
        out,
        manifest_path,
        source_label=source_label,
        source_sha256=mpq.sha256_bytes(source_bytes),
        displays=displays,
        server_dbc=server_dbc,
    )


def cmd_inspect(args) -> int:
    if args.archive:
        with mpq.Archive(args.archive) as archive:
            data = archive.read_file(ITEM_DBC_PATH)
    else:
        data = Path(args.dbc).read_bytes()
    dbc = ItemDbc.from_bytes(data)
    summary = dbc.summary()
    if args.ids:
        wanted = set()
        for part in args.ids.split(","):
            if "-" in part:
                start, end = part.split("-", 1)
                wanted.update(range(int(start), int(end) + 1))
            else:
                wanted.add(int(part))
        rows = [dbc.rows[item_id].to_dict() for item_id in sorted(wanted) if item_id in dbc.rows]
        summary["selected"] = rows
        summary["missing"] = sorted(item_id for item_id in wanted if item_id not in dbc.rows)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


def cmd_edit(args) -> int:
    dbc = ItemDbc.from_bytes(Path(args.dbc).read_bytes())
    before = len(dbc.rows)
    items = load_items(args.items)
    added, updated = dbc.upsert(items)
    dbc.validate()
    Path(args.out).write_bytes(dbc.to_bytes())
    print(
        f"{args.out}: rows {before} -> {len(dbc.rows)}; "
        f"added {len(added)}, updated {len(updated)}"
    )
    return 0


def cmd_build(args) -> int:
    if args.source_dbc:
        manifest = build_patch(
            args.source_dbc,
            args.items,
            args.out,
            args.manifest,
            source_label=args.source_label or str(args.source_dbc),
            server_dbc=args.server_dbc,
        )
    else:
        manifest = build_from_client(
            args.client,
            args.items,
            args.out,
            args.manifest,
            check_displays=not args.no_display_check,
            server_dbc=args.server_dbc,
        )
    dbc = manifest["dbc"][0]
    print(f"{manifest['archive']}: sha256 {manifest['sha256']}")
    print(
        f"  Item.dbc rows {dbc['rows_before']} -> {dbc['rows_after']}; "
        f"added {len(dbc['added_ids'])}, updated {len(dbc['updated_ids'])}"
    )
    print(f"  added IDs: {', '.join(str(item_id) for item_id in dbc['added_ids'])}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect = subparsers.add_parser("inspect", help="validate and summarize Item.dbc")
    group = inspect.add_mutually_exclusive_group(required=True)
    group.add_argument("--dbc")
    group.add_argument("--archive", help="MPQ containing DBFilesClient\\Item.dbc")
    inspect.add_argument("--ids", help="comma/range list, for example 901001-901020")
    inspect.set_defaults(func=cmd_inspect)

    edit = subparsers.add_parser("edit", help="upsert rows into an Item.dbc file")
    edit.add_argument("--dbc", required=True)
    edit.add_argument("--items", required=True)
    edit.add_argument("--out", required=True)
    edit.set_defaults(func=cmd_edit)

    build = subparsers.add_parser("build", help="build patch-X.MPQ with Item.dbc")
    build.add_argument("--client", default=os.environ.get("WOW_CLIENT", os.path.expanduser("~/Games/wotlk-clean")))
    build.add_argument("--items", required=True)
    build.add_argument("--out", required=True)
    build.add_argument("--manifest", required=True)
    build.add_argument("--source-dbc", help="use a local Item.dbc instead of the client")
    build.add_argument("--source-label", help="manifest label for --source-dbc")
    build.add_argument(
        "--server-dbc",
        help="server DataDir/dbc/Item.dbc; fails on server-only IDs or row conflicts",
    )
    build.add_argument("--no-display-check", action="store_true")
    build.set_defaults(func=cmd_build)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except (ItemDbcError, mpq.MpqError, OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
