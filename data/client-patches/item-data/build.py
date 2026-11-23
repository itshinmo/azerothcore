#!/usr/bin/env python3
"""Build data/client-patches/item-data/dist/patch-X.MPQ.

The patch contains one file: ``DBFilesClient\\Item.dbc``. It is built from the
highest-priority vendor Item.dbc below the project item patch, with the custom
rows from ``items.json`` upserted and sorted by ID. No other DBC is modified.

Usage::

    python3 data/client-patches/item-data/build.py
    python3 data/client-patches/item-data/build.py --check
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tools" / "client-patch"))

import generate_items  # noqa: E402
import item_dbc  # noqa: E402
import mpq  # noqa: E402

DEFAULT_CLIENT = os.environ.get("WOW_CLIENT", os.path.expanduser("~/Games/wotlk-clean"))
DEFAULT_ITEMS = HERE / "items.json"
DEFAULT_BATCH_CSV = generate_items.DEFAULT_BATCH_CSV
DEFAULT_BATCH_SQL = generate_items.DEFAULT_BATCH_SQL
DEFAULT_ITEM_DBC_SQL = generate_items.DEFAULT_ITEM_DBC_SQL
DEFAULT_OUT = HERE / "dist" / "patch-X.MPQ"
DEFAULT_MANIFEST = HERE / "manifest.json"


def rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.name


def build(args) -> int:
    out = Path(args.out).expanduser()
    manifest_path = Path(args.manifest).expanduser()
    if args.check:
        try:
            generate_items.validate_items(
                Path(args.items),
                Path(args.batch_csv),
                Path(args.batch_sql),
                Path(args.item_dbc_sql),
            )
        except generate_items.ItemsSourceError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1
        return check(out, manifest_path, args)

    generate_items.validate_items(
        Path(args.items),
        Path(args.batch_csv),
        Path(args.batch_sql),
        Path(args.item_dbc_sql),
    )
    manifest = item_dbc.build_from_client(
        args.client,
        args.items,
        out,
        manifest_path,
        check_displays=not args.no_display_check,
        server_dbc=args.server_dbc,
    )
    manifest["source_inputs"] = {
        "batch_csv": {
            "path": rel(Path(args.batch_csv)),
            "sha256": mpq.sha256_file(args.batch_csv),
        },
        "batch_sql": {
            "path": rel(Path(args.batch_sql)),
            "sha256": mpq.sha256_file(args.batch_sql),
        },
        "item_dbc_sql": {
            "path": rel(Path(args.item_dbc_sql)),
            "sha256": mpq.sha256_file(args.item_dbc_sql),
        },
    }
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    dbc = manifest["dbc"][0]
    print(f"{out}: sha256 {manifest['sha256']}")
    print(
        f"  Item.dbc rows {dbc['rows_before']} -> {dbc['rows_after']}; "
        f"added {len(dbc['added_ids'])}, updated {len(dbc['updated_ids'])}"
    )
    print(f"  added IDs: {', '.join(str(item_id) for item_id in dbc['added_ids'])}")
    print(f"  source: {dbc['source_archive']} ({dbc['source_sha256']})")
    print(f"wrote {manifest_path}")
    print()
    print("Install (client closed):")
    print(f"  cp {rel(out)} <client>/Data/patch-X.MPQ")
    print("Server (restart required; owner only):")
    print("  cp data/client-patches/item-data/dist/Item.dbc <server>/DataDir/dbc/Item.dbc")
    print("  or apply the same rows through the item_dbc table; do not half-apply")
    print("Rollback:")
    print("  rm <client>/Data/patch-X.MPQ")
    return 0


def check(out: Path, manifest_path: Path, args) -> int:
    if not out.is_file():
        raise SystemExit(f"patch not found: {out}")
    if not manifest_path.is_file():
        raise SystemExit(f"manifest not found: {manifest_path}")
    expected = json.loads(manifest_path.read_text(encoding="utf-8"))
    current_items = json.loads(Path(args.items).read_text(encoding="utf-8"))
    item_fields = (
        "id",
        "class",
        "subclass",
        "sound_override_subclass",
        "material",
        "display_info_id",
        "inventory_type",
        "sheathe_type",
    )
    current_values = [
        {field: row.get(field) for field in item_fields} for row in current_items
    ]
    if current_values != expected.get("items"):
        print("items.json data differs from manifest", file=sys.stderr)
        return 1
    current_items_hash = mpq.sha256_file(args.items)
    if current_items_hash != expected.get("items_sha256"):
        print(
            f"items.json sha256 {current_items_hash} != manifest {expected.get('items_sha256')}",
            file=sys.stderr,
        )
        return 1
    source_inputs = expected.get("source_inputs") or {}
    if not source_inputs:
        print("manifest has no source input hashes", file=sys.stderr)
        return 1
    for name, info in source_inputs.items():
        source_path = Path(info.get("path", ""))
        if not source_path.is_absolute():
            source_path = ROOT / source_path
        if not source_path.is_file():
            print(f"source input missing: {name}: {source_path}", file=sys.stderr)
            return 1
        if mpq.sha256_file(source_path) != info.get("sha256"):
            print(f"source input changed: {name}: {source_path}", file=sys.stderr)
            return 1
    actual = mpq.sha256_file(out)
    if actual != expected.get("sha256"):
        print(f"stale patch: sha256 {actual} != {expected.get('sha256')}", file=sys.stderr)
        return 1
    with mpq.Archive(out) as archive:
        names = {entry.name.lower() for entry in archive.list_files(include_internal=True)}
        if names != {
            item_dbc.ITEM_DBC_PATH.lower(),
            "(listfile)",
            "(attributes)",
        }:
            print(f"unexpected entries: {sorted(names)}", file=sys.stderr)
            return 1
        if archive.sha256(item_dbc.ITEM_DBC_PATH) != expected["dbc"][0]["output_sha256"]:
            print("Item.dbc sha256 mismatch", file=sys.stderr)
            return 1
        if not archive.verify_file(item_dbc.ITEM_DBC_PATH).ok:
            print("Item.dbc failed StormLib verify", file=sys.stderr)
            return 1
        server_dbc = out.parent / "Item.dbc"
        if not server_dbc.is_file() or (
            mpq.sha256_file(server_dbc) != expected["dbc"][0]["output_sha256"]
        ):
            print("server-side dist/Item.dbc is missing or stale", file=sys.stderr)
            return 1
        if args.server_dbc:
            input_hash = mpq.sha256_file(args.server_dbc)
            recorded = (expected.get("server_dbc_input") or {}).get("sha256")
            if recorded != input_hash:
                print(
                    f"server Item.dbc hash {input_hash} != manifest {recorded}",
                    file=sys.stderr,
                )
                return 1
        dbc = item_dbc.ItemDbc.from_bytes(archive.read_file(item_dbc.ITEM_DBC_PATH))
        for item in expected["items"]:
            row = dbc.rows.get(item["id"])
            if row is None or row.to_dict() != item:
                print(f"row mismatch or missing: {item['id']}", file=sys.stderr)
                return 1
    print(f"{out}: matches manifest ({actual})")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--client", default=DEFAULT_CLIENT)
    parser.add_argument("--items", default=str(DEFAULT_ITEMS))
    parser.add_argument("--batch-csv", default=str(DEFAULT_BATCH_CSV))
    parser.add_argument("--batch-sql", default=str(DEFAULT_BATCH_SQL))
    parser.add_argument("--item-dbc-sql", default=str(DEFAULT_ITEM_DBC_SQL))
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    parser.add_argument("--server-dbc", help="server DataDir/dbc/Item.dbc")
    parser.add_argument("--no-display-check", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        return build(args)
    except (
        generate_items.ItemsSourceError,
        item_dbc.ItemDbcError,
        mpq.MpqError,
        OSError,
        ValueError,
    ) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
