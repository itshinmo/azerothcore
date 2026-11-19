#!/usr/bin/env python3
"""Extract the WoW client's FrameXML template and font names for the addon harness.

Reads the FrameXML files out of the client's locale MPQs (later patches override
earlier ones), collects every virtual frame template and named Font, and writes
them to client-frames.txt next to this script. Requires mpyq:

    python3 -m pip install --user mpyq

Exit codes:
    0  list written
    2  client or MPQ error
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

OUT_NAME = "client-frames.txt"
ARCHIVES = ["locale-enUS.MPQ", "patch-enUS.MPQ", "patch-enUS-2.MPQ", "patch-enUS-3.MPQ"]
PAT_TEMPLATE = re.compile(r'<(\w+)\s+name="([^"]+)"[^>]*\bvirtual="true"')
PAT_FONT = re.compile(r'<Font\s+name="([^"]+)"')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", type=Path, default=Path.home() / "Games/wotlk-test",
                        help="WoW client directory holding Data/enUS/*.MPQ")
    parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parent / OUT_NAME)
    args = parser.parse_args()

    try:
        import mpyq
    except ImportError:
        print("error: mpyq not installed; run: python3 -m pip install --user mpyq", file=sys.stderr)
        return 2

    templates: set[str] = set()
    fonts: set[str] = set()
    for archive_name in ARCHIVES:
        archive_path = args.client / "Data/enUS" / archive_name
        if not archive_path.exists():
            print(f"error: missing {archive_path}", file=sys.stderr)
            return 2
        archive = mpyq.MPQArchive(str(archive_path))
        files = [f for f in archive.read_file("(listfile)").decode("utf-8", "replace").split("\r\n")
                 if f.startswith("Interface\\FrameXML\\")]
        for file_name in files:
            data = archive.read_file(file_name)
            if not data:
                continue
            text = data.decode("utf-8", "replace")
            templates.update(match.group(2) for match in PAT_TEMPLATE.finditer(text))
            fonts.update(match.group(1) for match in PAT_FONT.finditer(text))

    lines = [f"template {name}" for name in sorted(templates)]
    lines += [f"font {name}" for name in sorted(fonts)]
    args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{args.out}: {len(templates)} templates, {len(fonts)} fonts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
