#!/usr/bin/env python3
"""Inspect, verify, and build 3.3.5a client patch MPQs.

Examples::

    python3 tools/client-patch/client_patch.py inspect Data/patch-Z.MPQ
    python3 tools/client-patch/client_patch.py list Data/patch-Z.MPQ
    python3 tools/client-patch/client_patch.py which ~/Games/wotlk-clean/Data \
        'Interface\\FrameXML\\WorldMapFrame.lua'
    python3 tools/client-patch/client_patch.py extract Data/patch-Z.MPQ /tmp/out \
        'Interface\\FrameXML\\WorldMapFrame.lua'
    python3 tools/client-patch/client_patch.py pack build/patch-Z.MPQ build/root
    python3 tools/client-patch/client_patch.py verify build/patch-Z.MPQ \
        --manifest build/manifest.json
    python3 tools/client-patch/client_patch.py manifest build/patch-Z.MPQ \
        --out build/manifest.json

Set ``STORMLIB`` when StormLib is not in a default Homebrew path; see
``tools/client-patch/README.md`` and ``decisions/ADR-027``.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import mpq


def _print_json(value) -> None:
    print(json.dumps(value, indent=2, sort_keys=True, default=str))


def _human_size(value: int) -> str:
    number = float(value)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if number < 1024 or unit == "GiB":
            return f"{number:.1f} {unit}" if unit != "B" else f"{int(number)} B"
        number /= 1024
    return f"{value} B"


def _entry_json(entry: mpq.MpqEntry, archive: mpq.Archive | None = None) -> dict:
    data = {
        "path": entry.name,
        "size": entry.size,
        "compressed_size": entry.compressed_size,
        "flags": entry.flags,
        "locale": entry.locale,
    }
    if archive is not None and not entry.is_internal:
        data["sha256"] = archive.sha256(entry.name)
        result = archive.verify_file(entry.name)
        data["verify_flags"] = result.flags
        data["verify_ok"] = result.ok
    return data


def cmd_inspect(args) -> int:
    with mpq.Archive(args.archive) as archive:
        info = archive.inspect()
        entries = info.pop("entries")
        if args.json:
            info["file_entries"] = [_entry_json(entry) for entry in entries]
            _print_json(info)
            return 0
        header = info["header"]
        print(f"archive:      {info['path']}")
        print(f"sha256:       {info['sha256']}")
        print(f"size:         {_human_size(info['size'])}")
        print(f"format:       {info['format']}")
        if header.get("format_version") is not None:
            print(f"header:       {header['header_size']} bytes, sector {header['sector_size']}")
        print(f"files:        {info['files']}")
        print(f"uncompressed: {_human_size(info['uncompressed_size'])}")
        print(f"listfile:     {'yes' if info['listfile'] else 'no'}")
        print(f"attributes:   {'yes' if info['attributes'] else 'no'}")
        print(f"signature:    {'yes' if info['signature'] else 'no'}")
        if info["listfile"]:
            print(f"libstorm:     {mpq.stormlib_path()}")
        return 0


def cmd_list(args) -> int:
    with mpq.Archive(args.archive) as archive:
        entries = archive.list_files(mask=args.mask, include_internal=args.internal)
        if args.json:
            _print_json([_entry_json(entry, archive) for entry in entries])
            return 0
        for entry in entries:
            print(f"{entry.size:>12}  {entry.name}")
        return 0


def cmd_which(args) -> int:
    result = mpq.find_highest(
        args.data_dir, args.path, locale=args.locale, order=args.order
    )
    if args.json:
        _print_json(
            {
                "path": result.path,
                "winner": str(result.winner) if result.winner else None,
                "sources_low_to_high": [str(path) for path in result.sources],
                "skipped_unreadable": [str(path) for path in result.skipped],
                "locale": args.locale,
                "order": args.order,
            }
        )
        return 0 if result.winner else 1
    print(result.path)
    if result.winner:
        print(f"  winner: {result.winner}")
    else:
        print("  winner: none")
    if result.sources:
        print("  sources (low to high):")
        for path in result.sources:
            marker = ">" if path == result.winner else " "
            print(f"   {marker} {path}")
    if result.skipped:
        print("  skipped (unreadable):", file=sys.stderr)
        for path in result.skipped:
            print(f"    {path}", file=sys.stderr)
    return 0 if result.winner else 1


def cmd_extract(args) -> int:
    destination = Path(args.destination).expanduser()
    with mpq.Archive(args.archive) as archive:
        names = archive.listfile() if args.all else args.names
        if not names:
            print("give one or more paths, or --all", file=sys.stderr)
            return 2
        for name in names:
            target = mpq.safe_destination(destination, name)
            if target.exists() and not args.force:
                print(f"refusing to overwrite {target} (use --force)", file=sys.stderr)
                return 1
            extracted = archive.extract(name, destination)
            print(extracted)
    return 0


def _source_files(source: Path, prefix: str) -> list[tuple[Path, str]]:
    if source.is_file():
        return [(source, prefix or source.name)]
    if not source.is_dir():
        raise SystemExit(f"source not found: {source}")
    files = []
    for path in sorted(item for item in source.rglob("*") if item.is_file()):
        relative = path.relative_to(source).as_posix().replace("/", "\\")
        name = f"{prefix}\\{relative}" if prefix else relative
        files.append((path, name))
    return files


def cmd_pack(args) -> int:
    output = Path(args.output).expanduser()
    if output.exists() and not args.force:
        print(f"refusing to overwrite {output} (use --force)", file=sys.stderr)
        return 1
    files: list[tuple[Path, str]] = []
    for item in args.source:
        source, _, prefix = item.partition(":")
        files.extend(_source_files(Path(source).expanduser(), prefix.replace("/", "\\")))
    if not files:
        print("no files to pack", file=sys.stderr)
        return 2
    seen = {}
    for path, name in files:
        key = name.lower()
        if key in seen:
            print(f"duplicate archive path: {name} (also {seen[key]})", file=sys.stderr)
            return 2
        seen[key] = name
    if args.compression == "none":
        compression = mpq.MPQ_COMPRESSION_NONE
    else:
        compression = mpq.MPQ_COMPRESSION_ZLIB
    if output.exists():
        output.unlink()
    with mpq.Archive.create(output, max_files=max(16, len(files) * 2)) as archive:
        for path, name in files:
            archive.add_file(path, name, compression=compression)
    with mpq.Archive(output) as archive:
        entries = archive.list_files()
        print(f"{output}: {len(entries)} files, {_human_size(archive.path.stat().st_size)}")
        for entry in entries:
            print(f"  {entry.size:>10}  {entry.name}")
    return 0


def _manifest(archive: mpq.Archive, sources: list[str] | None = None) -> dict:
    entries = []
    for entry in archive.list_files():
        result = archive.verify_file(entry.name)
        entries.append(
            {
                "path": entry.name,
                "size": entry.size,
                "compressed_size": entry.compressed_size,
                "sha256": archive.sha256(entry.name),
                "verify_flags": result.flags,
                "verify_ok": result.ok,
            }
        )
    info = archive.inspect()
    return {
        "schema": 1,
        "archive": archive.path.name,
        "sha256": info["sha256"],
        "size": info["size"],
        "format": info["format"],
        "compression": "zlib",
        "sources": sources or [],
        "entries": entries,
    }


def cmd_manifest(args) -> int:
    with mpq.Archive(args.archive) as archive:
        manifest = _manifest(archive, args.source)
    text = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    if args.out:
        Path(args.out).write_text(text, encoding="utf-8")
        print(f"wrote {args.out}")
    else:
        print(text, end="")
    return 0


def cmd_verify(args) -> int:
    failures = 0
    with mpq.Archive(args.archive) as archive:
        if args.manifest:
            expected = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
            actual_hash = mpq.sha256_file(archive.path)
            if actual_hash != expected.get("sha256"):
                print(
                    f"archive sha256 mismatch: {actual_hash} != {expected.get('sha256')}",
                    file=sys.stderr,
                )
                failures += 1
            expected_entries = {entry["path"]: entry for entry in expected.get("entries", [])}
            actual_entries = {entry.name: entry for entry in archive.list_files()}
            for name in sorted(set(expected_entries) | set(actual_entries)):
                if name not in actual_entries:
                    print(f"missing entry: {name}", file=sys.stderr)
                    failures += 1
                    continue
                if name not in expected_entries:
                    print(f"unexpected entry: {name}", file=sys.stderr)
                    failures += 1
                    continue
                if expected_entries[name].get("sha256") != archive.sha256(name):
                    print(f"sha256 mismatch: {name}", file=sys.stderr)
                    failures += 1
        for entry in archive.list_files(include_internal=True):
            result = archive.verify_file(entry.name)
            status = "ok" if result.ok else f"FAILED flags={result.flags:#06x}"
            if args.verbose:
                print(f"{status:20} {entry.name}")
            if not result.ok:
                failures += 1
        print(
            f"{archive.path}: {len(archive.list_files())} files, "
            f"{'ok' if failures == 0 else str(failures) + ' failure(s)'}"
        )
    return 0 if failures == 0 else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect = subparsers.add_parser("inspect", help="show archive metadata")
    inspect.add_argument("archive")
    inspect.add_argument("--json", action="store_true")
    inspect.set_defaults(func=cmd_inspect)

    list_parser = subparsers.add_parser("list", help="list archive entries")
    list_parser.add_argument("archive")
    list_parser.add_argument("--mask", default="*")
    list_parser.add_argument("--internal", action="store_true", help="include (listfile) etc.")
    list_parser.add_argument("--json", action="store_true")
    list_parser.set_defaults(func=cmd_list)

    which = subparsers.add_parser(
        "which", help="find the highest-priority archive for a client path"
    )
    which.add_argument("data_dir", help="client Data directory")
    which.add_argument("path", help="client path, for example Interface\\FrameXML\\X.lua")
    which.add_argument("--locale", default="enUS")
    which.add_argument(
        "--order",
        choices=("english", "localized"),
        default="english",
        help="archive priority shape (default: English client)",
    )
    which.add_argument("--json", action="store_true")
    which.set_defaults(func=cmd_which)

    extract = subparsers.add_parser("extract", help="extract entries safely")
    extract.add_argument("archive")
    extract.add_argument("destination")
    extract.add_argument("names", nargs="*")
    extract.add_argument("--all", action="store_true")
    extract.add_argument("--force", action="store_true")
    extract.set_defaults(func=cmd_extract)

    pack = subparsers.add_parser("pack", help="create an MPQ v1 archive from files")
    pack.add_argument("output")
    pack.add_argument(
        "source",
        nargs="+",
        help="file or directory, optionally followed by :archive/prefix",
    )
    pack.add_argument("--compression", choices=("zlib", "none"), default="zlib")
    pack.add_argument("--force", action="store_true")
    pack.set_defaults(func=cmd_pack)

    manifest = subparsers.add_parser("manifest", help="write an entry manifest")
    manifest.add_argument("archive")
    manifest.add_argument("--out")
    manifest.add_argument("--source", action="append", default=[])
    manifest.set_defaults(func=cmd_manifest)

    verify = subparsers.add_parser("verify", help="verify archive contents")
    verify.add_argument("archive")
    verify.add_argument("--manifest")
    verify.add_argument("--verbose", action="store_true")
    verify.set_defaults(func=cmd_verify)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except (mpq.MpqError, ValueError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
