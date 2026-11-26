#!/usr/bin/env python3
"""Build patch-V.MPQ: extended race/class creation DBCs.

Carries two whole-file DBCs from the effective client sources:

- CharBaseInfo.dbc: 62 effective rows + 5 proposed pairs = 67 rows.
- CharStartOutfit.dbc: 126 effective rows + 8 rows (4 pairs x 2 genders) = 134 rows.

The patch is a proposal artifact. It is not installed on the live client.

    python3 build.py --client-data ~/Games/wotlk-clean/Data
    python3 build.py --check

Layout follows the client-patch contract: build.py,
dist/patch-V.MPQ, manifest.json, README.md, LEDGER.md.

Record sizes are taken from the DBC headers and checked against the physical layout:
CharBaseInfo has 2-byte records; CharStartOutfit has 296-byte records
(4 + 3*1 + 1 + 24*4 + 48*4). Do not use field_count * 4 for CharStartOutfit: the byte
fields and padding make 77 declared fields a 296-byte row, not 308.
"""

import argparse
import ctypes
import hashlib
import json
import os
import shutil
import struct
import sys
import tempfile
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))

CHARBASE_SOURCE_ARCHIVE = "locale-enUS.MPQ"
CHARBASE_SOURCE_ARCHIVE_SHA256 = (
    "45f02a3bf3964b169f397cea58113cdce5fa7bdf58d4b63f68e46255bb3bd3ea"
)
CHARBASE_SOURCE_DBC_SHA256 = (
    "1e81c6f8a218b187187c9f13e65cad39920aab56a57f2955d72385d94fee2e25"
)
CHARBASE_OUTPUT_DBC_SHA256 = (
    "23dbf975092271ca511eb6378c30697e6f2fec1ccf195ab9680977f8a43fa505"
)

OUTFIT_SOURCE_ARCHIVE = "patch-enUS-2.MPQ"
OUTFIT_SOURCE_ARCHIVE_SHA256 = (
    "ab9af8457f0d7b99a562f26b7d1651bbf68ebc37ddb249d01ac860ccc8746ff4"
)
OUTFIT_SOURCE_DBC_SHA256 = (
    "a026407cd4fa60867ac2eda1070e89679e811774b476980902125f6d5af61540"
)
OUTFIT_OUTPUT_DBC_SHA256 = (
    "03ab1105f505293bb89204c5a5fc88a49527c06c1eab2bddf34b979ca7d3ee52"
)

CHARBASE_ADDED = [(2, 8), (3, 8), (7, 5), (8, 9), (10, 1)]

# New outfit row id -> (race, class, gender, source race, source class, source gender).
OUTFIT_ADDED = {
    950400: (2, 8, 0, 5, 8, 0),
    950401: (2, 8, 1, 5, 8, 1),
    950402: (7, 5, 0, 1, 5, 0),
    950403: (7, 5, 1, 1, 5, 1),
    950404: (8, 9, 0, 2, 9, 0),
    950405: (8, 9, 1, 2, 9, 1),
    950406: (10, 1, 0, 2, 1, 0),
    950407: (10, 1, 1, 2, 1, 1),
}

FIXED_TIME = 1640995200  # 2022-01-01T00:00:00Z

LOAD_ORDER = {
    "client": "3.3.5a (12340), English",
    "order": (
        "locale non-patch; locale numeric patches; locale alphabetic patches; base non-patch; "
        "base numeric patches; base alphabetic patches (one chain, later archives win)"
    ),
    "project_family": [
        "Data/patch-V.MPQ",
        "Data/patch-X.MPQ",
        "Data/patch-Y.MPQ",
        "Data/patch-Z.MPQ",
    ],
    "expected_winner": "Data/patch-V.MPQ",
    "sources": [
        {"path": f"Data/enUS/{CHARBASE_SOURCE_ARCHIVE}",
         "sha256": CHARBASE_SOURCE_ARCHIVE_SHA256, "role": "effective CharBaseInfo source"},
        {"path": f"Data/enUS/{OUTFIT_SOURCE_ARCHIVE}",
         "sha256": OUTFIT_SOURCE_ARCHIVE_SHA256, "role": "effective CharStartOutfit source"},
    ],
}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def stormlib():
    lib = ctypes.CDLL(os.environ.get("STORMLIB", "/opt/homebrew/lib/libstorm.dylib"))
    handle = ctypes.c_void_p
    lib.SFileOpenArchive.argtypes = [ctypes.c_char_p, ctypes.c_uint, ctypes.c_uint,
                                     ctypes.POINTER(handle)]
    lib.SFileCreateArchive.argtypes = [ctypes.c_char_p, ctypes.c_uint, ctypes.c_uint,
                                       ctypes.POINTER(handle)]
    lib.SFileExtractFile.argtypes = [handle, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    lib.SFileAddFileEx.argtypes = [handle, ctypes.c_char_p, ctypes.c_char_p,
                                   ctypes.c_uint, ctypes.c_uint, ctypes.c_uint]
    lib.SFileOpenFileEx.argtypes = [handle, ctypes.c_char_p, ctypes.c_uint,
                                    ctypes.POINTER(handle)]
    lib.SFileGetFileInfo.argtypes = [handle, ctypes.c_int, ctypes.c_void_p, ctypes.c_uint,
                                     ctypes.c_void_p]
    lib.SFileGetFileInfo.restype = ctypes.c_bool
    lib.SFileVerifyFile.argtypes = [handle, ctypes.c_char_p, ctypes.c_uint]
    lib.SFileVerifyFile.restype = ctypes.c_uint
    lib.SFileCloseFile.argtypes = [handle]
    lib.SFileCloseArchive.argtypes = [handle]
    return lib, handle


def extract(archive, names, folder):
    lib, handle = stormlib()
    h = handle()
    if not lib.SFileOpenArchive(archive.encode(), 0, 0x100, ctypes.byref(h)):
        sys.exit(f"can't open {archive}")
    out = {}
    try:
        for name in names:
            dst = os.path.join(folder, name.replace("\\", "_"))
            if not lib.SFileExtractFile(h, name.encode(), dst.encode(), 0):
                raise RuntimeError(f"can't extract {name} from {archive}")
            out[name] = dst
    finally:
        lib.SFileCloseArchive(h)
    return out


def pack(out, files):
    lib, handle = stormlib()
    if os.path.exists(out):
        os.remove(out)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    h = handle()
    if not lib.SFileCreateArchive(out.encode(), 0x00300000, max(16, len(files) * 2),
                                  ctypes.byref(h)):
        sys.exit(f"can't create {out}")
    try:
        for src, name in files:
            os.utime(src, (FIXED_TIME, FIXED_TIME))
            if not lib.SFileAddFileEx(h, src.encode(), name.encode(), 0x80000200, 0x02, 0x02):
                raise RuntimeError(f"can't add {name}")
    except BaseException:
        lib.SFileCloseArchive(h)
        if os.path.exists(out):
            os.remove(out)
        raise
    lib.SFileCloseArchive(h)


def entries(archive):
    lib, handle = stormlib()
    h = handle()
    if not lib.SFileOpenArchive(archive.encode(), 0, 0x100, ctypes.byref(h)):
        sys.exit(f"can't open {archive}")
    result = []
    try:
        for name in sorted(ENTRY_PATHS):
            hf = handle()
            if not lib.SFileOpenFileEx(h, name.encode(), 0, ctypes.byref(hf)):
                raise RuntimeError(f"{archive}: missing {name}")
            try:
                size = ctypes.c_uint(0)
                csize = ctypes.c_uint(0)
                if not lib.SFileGetFileInfo(hf, 51, ctypes.byref(size), 4, None):
                    raise RuntimeError(f"{archive}: no size for {name}")
                if not lib.SFileGetFileInfo(hf, 52, ctypes.byref(csize), 4, None):
                    raise RuntimeError(f"{archive}: no compressed size for {name}")
            finally:
                lib.SFileCloseFile(hf)
            flags = int(lib.SFileVerifyFile(h, name.encode(), 0x0000000F))
            result.append({
                "path": name,
                "size": size.value,
                "compressed_size": csize.value,
                "verify_flags": flags,
                "verify_ok": (flags & 0x02AB) == 0,
            })
    finally:
        lib.SFileCloseArchive(h)
    return result


ENTRY_PATHS = [
    r"DBFilesClient\CharBaseInfo.dbc",
    r"DBFilesClient\CharStartOutfit.dbc",
]


def read_dbc(path):
    data = open(path, "rb").read()
    magic, rows, fields, record_size, string_size = struct.unpack("<4sIIII", data[:20])
    if magic != b"WDBC":
        sys.exit(f"{path}: not a WDBC file")
    if len(data) != 20 + rows * record_size + string_size:
        sys.exit(f"{path}: header sizes do not match file length")
    return data, rows, fields, record_size, string_size


def char_base_info(src, dst):
    data, rows, fields, record_size, string_size = read_dbc(src)
    if fields != 2 or record_size != 2:
        sys.exit(f"{src}: expected 2 fields, 2-byte records")
    body = data[20:20 + rows * record_size]
    strings = data[20 + rows * record_size:]
    new_rows = [body[i * record_size:(i + 1) * record_size] for i in range(rows)]
    new_rows += [bytes(pair) for pair in CHARBASE_ADDED]
    new_rows.sort()
    out = b"WDBC" + struct.pack("<IIII", len(new_rows), fields, record_size, string_size)
    out += b"".join(new_rows) + strings
    open(dst, "wb").write(out)
    return rows, len(new_rows)


def char_start_outfit(src, dst):
    data, rows, fields, record_size, string_size = read_dbc(src)
    physical = 4 + 3 * 1 + 1 + 24 * 4 + 48 * 4  # d, bbb, X, items, display/slot padding
    if fields != 77 or record_size != physical:
        sys.exit(f"{src}: expected 77 fields and a {physical}-byte physical row, "
                 f"got {fields}/{record_size}. Do not use field_count * 4 for this table.")
    body = data[20:20 + rows * record_size]
    strings = data[20 + rows * record_size:]
    source_rows = [body[i * record_size:(i + 1) * record_size] for i in range(rows)]
    by_key = {}
    for row in source_rows:
        race, cls, gender = struct.unpack("<BBB", row[4:7])
        by_key[(race, cls, gender)] = row
    new_rows = list(source_rows)
    for new_id, (race, cls, gender, srace, scls, sgender) in sorted(OUTFIT_ADDED.items()):
        key = (srace, scls, sgender)
        if key not in by_key:
            sys.exit(f"{src}: missing source outfit {key}")
        row = bytearray(by_key[key])
        struct.pack_into("<I", row, 0, new_id)
        row[4], row[5], row[6] = race, cls, gender
        new_rows.append(bytes(row))
    out = b"WDBC" + struct.pack("<IIII", len(new_rows), fields, record_size, string_size)
    out += b"".join(new_rows) + strings
    open(dst, "wb").write(out)
    return rows, len(new_rows)


def build(args):
    client_data = os.path.abspath(os.path.expanduser(args.client_data))
    for archive, expected in [
        (CHARBASE_SOURCE_ARCHIVE, CHARBASE_SOURCE_ARCHIVE_SHA256),
        (OUTFIT_SOURCE_ARCHIVE, OUTFIT_SOURCE_ARCHIVE_SHA256),
    ]:
        path = os.path.join(client_data, "enUS", archive)
        if sha256(path) != expected:
            sys.exit(f"{path}: unexpected archive hash; client data changed")

    folder = tempfile.mkdtemp(prefix="race-class-combos-")
    try:
        charbase_src = extract(os.path.join(client_data, "enUS", CHARBASE_SOURCE_ARCHIVE),
                               [ENTRY_PATHS[0]], folder)[ENTRY_PATHS[0]]
        outfit_src = extract(os.path.join(client_data, "enUS", OUTFIT_SOURCE_ARCHIVE),
                             [ENTRY_PATHS[1]], folder)[ENTRY_PATHS[1]]
        if sha256(charbase_src) != CHARBASE_SOURCE_DBC_SHA256:
            sys.exit("CharBaseInfo.dbc: unexpected source hash")
        if sha256(outfit_src) != OUTFIT_SOURCE_DBC_SHA256:
            sys.exit("CharStartOutfit.dbc: unexpected source hash")

        charbase_out = os.path.join(folder, "CharBaseInfo.dbc")
        outfit_out = os.path.join(folder, "CharStartOutfit.dbc")
        cb_before, cb_after = char_base_info(charbase_src, charbase_out)
        co_before, co_after = char_start_outfit(outfit_src, outfit_out)
        if sha256(charbase_out) != CHARBASE_OUTPUT_DBC_SHA256:
            sys.exit("CharBaseInfo.dbc: output hash changed")
        if sha256(outfit_out) != OUTFIT_OUTPUT_DBC_SHA256:
            sys.exit("CharStartOutfit.dbc: output hash changed")

        pack(args.out, [(charbase_out, ENTRY_PATHS[0]), (outfit_out, ENTRY_PATHS[1])])
    finally:
        shutil.rmtree(folder)

    folder = tempfile.mkdtemp(prefix="race-class-combos-check-")
    try:
        check = extract(args.out, ENTRY_PATHS, folder)
        if sha256(check[ENTRY_PATHS[0]]) != CHARBASE_OUTPUT_DBC_SHA256:
            sys.exit("CharBaseInfo.dbc does not round-trip")
        if sha256(check[ENTRY_PATHS[1]]) != OUTFIT_OUTPUT_DBC_SHA256:
            sys.exit("CharStartOutfit.dbc does not round-trip")
    finally:
        shutil.rmtree(folder)

    manifest_entries = entries(args.out)
    for entry in manifest_entries:
        entry["sha256"] = (
            CHARBASE_OUTPUT_DBC_SHA256 if entry["path"] == ENTRY_PATHS[0]
            else OUTFIT_OUTPUT_DBC_SHA256
        )

    manifest = {
        "schema": 1,
        "archive": os.path.basename(args.out),
        "sha256": sha256(args.out),
        "size": os.path.getsize(args.out),
        "format": "MPQ v1",
        "compression": "zlib",
        "built_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "dbc_files": 2,
        "dbc": {
            "CharBaseInfo.dbc": {
                "source_archive": f"Data/enUS/{CHARBASE_SOURCE_ARCHIVE}",
                "source_archive_sha256": CHARBASE_SOURCE_ARCHIVE_SHA256,
                "source_dbc_sha256": CHARBASE_SOURCE_DBC_SHA256,
                "output_dbc_sha256": CHARBASE_OUTPUT_DBC_SHA256,
                "source_rows": cb_before,
                "rows": cb_after,
                "fields": 2,
                "record_size": 2,
                "added": [f"{race},{cls}" for race, cls in CHARBASE_ADDED],
            },
            "CharStartOutfit.dbc": {
                "source_archive": f"Data/enUS/{OUTFIT_SOURCE_ARCHIVE}",
                "source_archive_sha256": OUTFIT_SOURCE_ARCHIVE_SHA256,
                "source_dbc_sha256": OUTFIT_SOURCE_DBC_SHA256,
                "output_dbc_sha256": OUTFIT_OUTPUT_DBC_SHA256,
                "source_rows": co_before,
                "rows": co_after,
                "fields": 77,
                "record_size": 296,
                "added": [str(row_id) for row_id in sorted(OUTFIT_ADDED)],
            },
        },
        "load_order": LOAD_ORDER,
        "sources": [
            f"Data/enUS/{CHARBASE_SOURCE_ARCHIVE}: DBFilesClient\\CharBaseInfo.dbc "
            f"(sha256 {CHARBASE_SOURCE_DBC_SHA256})",
            f"Data/enUS/{OUTFIT_SOURCE_ARCHIVE}: DBFilesClient\\CharStartOutfit.dbc "
            f"(sha256 {OUTFIT_SOURCE_DBC_SHA256})",
        ],
        "entries": manifest_entries,
    }
    with open(args.manifest, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print(f"{args.out}: 2 files, {manifest['size']} bytes, sha256 {manifest['sha256']}")
    print(f"{args.manifest}: written")


def check(args):
    with open(args.manifest, encoding="utf-8") as f:
        manifest = json.load(f)
    if sha256(args.out) != manifest["sha256"]:
        sys.exit(f"{args.out}: hash differs from {args.manifest}")
    if manifest.get("schema") != 1 or manifest.get("dbc_files") != 2:
        sys.exit(f"{args.manifest}: not a schema 1, dbc_files 2 manifest")
    folder = tempfile.mkdtemp(prefix="race-class-combos-check-")
    try:
        names = [entry["path"] for entry in manifest["entries"]]
        paths = extract(args.out, names, folder)
        for entry in manifest["entries"]:
            if sha256(paths[entry["path"]]) != entry["sha256"]:
                sys.exit(f"{args.out}: {entry['path']} differs from the manifest")
    finally:
        shutil.rmtree(folder)
    print(f"{args.out}: {len(manifest['entries'])} files verified against {args.manifest}")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--client-data", default="~/Games/wotlk-clean/Data")
    parser.add_argument("--out", default=os.path.join(HERE, "dist", "patch-V.MPQ"))
    parser.add_argument("--manifest", default=os.path.join(HERE, "manifest.json"))
    parser.add_argument("--check", action="store_true",
                        help="verify an existing archive and manifest")
    args = parser.parse_args()
    if args.check:
        check(args)
    else:
        build(args)


if __name__ == "__main__":
    main()
