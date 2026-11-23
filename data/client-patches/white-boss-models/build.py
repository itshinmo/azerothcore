#!/usr/bin/env python3
"""Build patch-Y.MPQ: restore the stock 3.3.5a goblin male model.

The Ascension character pack (patch-A.MPQ) replaces Character\\Goblin\\Male\\GoblinMale.m2 with a
converted HD model whose texture mapping sends most of the body to the character hair and cape
slots, so the goblin bake only reaches part of the model and the rest draws white. The stock model
and its three skins in common-2.MPQ are intact, so this patch overlays the stock model, skins and
the 32 external animations the stock client ships for it.

Layout follows specs/client-patch.md (unmerged, branch feat/map-poi): build.py, dist/patch-Y.MPQ,
manifest.json in the contract schema, README.md, and this script's pinned inputs.

    python3 build.py --client-data ~/Games/wotlk-clean/Data
    python3 build.py --check

The source archive, every entry and the archive itself are hash-pinned. File times are pinned too,
so a rebuild produces the same archive bytes; only manifest.json's built_at changes.
"""

import argparse
import ctypes
import hashlib
import json
import os
import shutil
import sys
import tempfile
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE_ARCHIVE = "common-2.MPQ"
SOURCE_SHA256 = "9c605d95443172bdfd7c6936bc636684761241657935c22da25f955083809f43"
REPLACED_ARCHIVE = "patch-A.MPQ"  # carries the broken replacement model
REPLACED_SHA256 = "992b5f3e6badc960b2eb68b976f5be42ae5f1e1416ccb43833fbbc6cfe6c2b94"

# Fixed file time in the packed entries keeps (attributes) stable and the archive byte-identical.
FIXED_TIME = 1640995200  # 2022-01-01T00:00:00Z

# path in the client -> sha256 of the stock file in common-2.MPQ
FILES = {
    r"Character\Goblin\Male\GoblinMale.m2":
        "57ce1c7597534331bd3ddafe5352aaccca658f88f13a839b6e9689f97e81d9c0",
    r"Character\Goblin\Male\GoblinMale00.skin":
        "4141b0d281191164cb84c5640addcfd0c26c5be85eeb2b2ad6a25e5ca00f67fb",
    r"Character\Goblin\Male\GoblinMale01.skin":
        "f906bfd4c36401645776c018d39f1c43d4bd09db92508838c319c48155c3fb3f",
    r"Character\Goblin\Male\GoblinMale02.skin":
        "5c9aa67fd884c7e48054b19a6fd17ce0e53f006ddbd929ac4b2efce2c4cd0444",
}

ANIMS = {
    "0062": "82a3937b14f832fa2fd5661938b9d49d8d66a90ce93d48d2d9973d1330b95335",
    "0064": "1b84749a212b7b0fd9fa1163c41ab4cc3712cf54028848023eeddd3a3f8bcc7d",
    "0065": "4a7b14d382e8fb7c1af41a47fead03510fa560a9524bf2c3e0fb140a9cd3c327",
    "0066": "dea6a659ec3ad5541fbabe7c9f205e2d316c6f5a7aba171b18f22da0599eb07a",
    "0067": "b6f2d6a0157fe16d4169385219f44a874f023645916c988708995e7b522063ee",
    "0068": "0c6f8a5403b826d47cc14f8947b6539e280fe82cf3d192573088879cab6e547c",
    "0069": "04d18d8f2c8e2ffa0728847d3c9f5ec068f8fe7192b5e31d6ad3438ea3b5fd5f",
    "0070": "fdf5d4fc98f9788bb104cab59e1165f656c6718c6a2af434f96519d76e34432c",
    "0073": "5a59a6ca5946473de2a296880cd0ea5888418e0328fc65da3a73bae40306d66a",
    "0074": "ba05668adc7c4ddbaa735d1da85dbe31c764087ac0b3d82b07a089ad7ad52453",
    "0076": "da0216aa8ffdeee853d3aa177f6da17dfac7def8d0b9fd75904152624e4cb5ea",
    "0077": "640343bfc870f2ba376e347c091da1595b9a2fcf8feaeec6ed29864860552edc",
    "0078": "6ea6ab755c4a3982c45942e50bb93ad7fedbbe55546d361aed6d6d3d75d41775",
    "0079": "702ba9c9dac7fd7554fa26e39b64edee595f68846db335b9358e5f9eb79d68a2",
    "0080": "2d5ee2914d22ed24ac134d6ec62fbed79ece738fe7fc8069a25dd683b999945f",
    "0081": "f30d24d92a3958fac76eaf395b34b14c6a3a4dc3642e60d7254a462097f97838",
    "0082": "d5e3383e2556b522a519df85dd2d380f44a67884ab1e5d2a3c80de001b1bebb7",
    "0083": "48d595fb63d4382fd362a883b7b2670c97787783e2bb43242f888680c05435c2",
    "0084": "10bd76b9d4bc69d68da9250ecd1ffe474d0fb1c45eb2a9093649a9d538eb6328",
    "0096": "6ccccaa5dac526da9a24e2725b60b73ed12c285426e7139c72ecd655141919ea",
    "0097": "6eca2f56c6e4b241f235912e2d49897ca333dd114ee5d1e55d6df2e3268f0ffa",
    "0098": "e9dd7d901a639b0746bb751f9b6de087369dd0d97f073cd7b35f018e2a573f14",
    "0099": "58881578698d3fd6d2086b68e7628f40bd77560fca1f0b5b2d76acedc8c38218",
    "0100": "7f2e7220abcac46a4e93a81eab1f9bdaa3cc98fc9bd9ad924dab27c5158a4d52",
    "0101": "10aa5427dd11404dd43966c5701eaf4680a1d17812361d5bd656e94207e6016d",
    "0102": "dec34b6d799812431fc7451a9e663b5105fc03d8765a584b87e0dd8b2694a3cc",
    "0103": "39a28eefa28514adc00ede3feecbbf2828fba14a3899daf8f5d40a8da513703d",
    "0104": "659c44d7b191f5aa3cd8387cbe62ea6741ef5e04c3fe736bcf68410899ffd55e",
    "0113": "063e3e24496038936d60349ed50d3562543375caa2320b4457c3831a58428c7a",
    "0123": "dcea52ecbbd1fe465f947fa7568913d512058fcd3f87f3b3c72d47b753e72437",
    "0128": "e668e38a39338ef88b0c16862edbe2aa036d5feb139c14de02c29def853991be",
    "0129": "85ff7c6cc7769a280f98ff9f0c6daddeef02bae01a3573cbf2c5d0eb0045d7b4",
}

LOAD_ORDER = {
    "client": "3.3.5a (12340), English",
    "order": "locale non-patch; locale numeric patches; locale alphabetic patches; base non-patch; "
             "base numeric patches; base alphabetic patches (one chain, later archives win)",
    "project_family": ["Data/patch-X.MPQ", "Data/patch-Y.MPQ", "Data/patch-Z.MPQ"],
    "expected_winner": "Data/patch-Y.MPQ",
    "sources": [
        {"path": "Data/common-2.MPQ", "sha256": SOURCE_SHA256, "role": "stock source"},
        {"path": "Data/patch-A.MPQ", "sha256": REPLACED_SHA256,
         "role": "broken replacement, overridden by this patch"},
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
    lib.SFileOpenArchive.argtypes = [ctypes.c_char_p, ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(handle)]
    lib.SFileCreateArchive.argtypes = [ctypes.c_char_p, ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(handle)]
    lib.SFileExtractFile.argtypes = [handle, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    lib.SFileAddFileEx.argtypes = [handle, ctypes.c_char_p, ctypes.c_char_p,
                                   ctypes.c_uint, ctypes.c_uint, ctypes.c_uint]
    lib.SFileOpenFileEx.argtypes = [handle, ctypes.c_char_p, ctypes.c_uint, ctypes.POINTER(handle)]
    lib.SFileGetFileInfo.argtypes = [handle, ctypes.c_int, ctypes.c_void_p, ctypes.c_uint, ctypes.c_void_p]
    lib.SFileGetFileInfo.restype = ctypes.c_bool
    lib.SFileVerifyFile.argtypes = [handle, ctypes.c_char_p, ctypes.c_uint]
    lib.SFileVerifyFile.restype = ctypes.c_uint
    lib.SFileCloseFile.argtypes = [handle]
    lib.SFileCloseArchive.argtypes = [handle]
    return lib, handle


def pack(out, files):
    """Create the MPQ and remove a half-written file if adding an entry fails."""
    lib, handle = stormlib()
    if os.path.exists(out):
        os.remove(out)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    h = handle()
    # MPQ v1 with a listfile and attributes; each file zlib-compressed, like the other client patches.
    if not lib.SFileCreateArchive(out.encode(), 0x00300000, max(16, len(files) * 2), ctypes.byref(h)):
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


def entries(archive):
    """Manifest entries in the client-patch schema: sizes, hash, StormLib verify flags."""
    lib, handle = stormlib()
    h = handle()
    if not lib.SFileOpenArchive(archive.encode(), 0, 0x100, ctypes.byref(h)):
        sys.exit(f"can't open {archive}")
    result = []
    try:
        for name in sorted(expected_files()):
            hf = handle()
            if not lib.SFileOpenFileEx(h, name.encode(), 0, ctypes.byref(hf)):
                raise RuntimeError(f"{archive}: missing {name}")
            try:
                size = ctypes.c_uint(0)
                csize = ctypes.c_uint(0)
                # SFileInfoFileSize = 51, SFileInfoCompressedSize = 52 (StormLib.h enum).
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
                # Same error mask as the pipeline tool: CRC/size/checksum failures set these bits.
                "verify_ok": (flags & 0x02AB) == 0,
            })
    finally:
        lib.SFileCloseArchive(h)
    return result


def expected_files():
    files = dict(FILES)
    for anim, digest in ANIMS.items():
        files[rf"Character\Goblin\Male\GoblinMale{anim}-00.anim"] = digest
    return files


def build(args):
    client_data = os.path.abspath(os.path.expanduser(args.client_data))
    source = os.path.join(client_data, SOURCE_ARCHIVE)
    if sha256(source) != SOURCE_SHA256:
        sys.exit(f"{source}: unexpected archive hash; client data changed")
    files = expected_files()
    folder = tempfile.mkdtemp(prefix="white-boss-models-")
    try:
        paths = extract(source, sorted(files), folder)
        for name, digest in files.items():
            if sha256(paths[name]) != digest:
                sys.exit(f"{name}: unexpected source hash; client data changed")
        pack(args.out, [(paths[name], name) for name in sorted(files)])
    finally:
        shutil.rmtree(folder)

    # Verify the archive: every entry must extract back byte for byte.
    folder = tempfile.mkdtemp(prefix="white-boss-models-verify-")
    try:
        check = extract(args.out, sorted(files), folder)
        for name, digest in files.items():
            if sha256(check[name]) != digest:
                sys.exit(f"{args.out}: {name} does not round-trip")
        manifest_entries = entries(args.out)
        for entry in manifest_entries:
            entry["sha256"] = sha256(check[entry["path"]])
    finally:
        shutil.rmtree(folder)

    manifest = {
        "schema": 1,
        "archive": os.path.basename(args.out),
        "sha256": sha256(args.out),
        "size": os.path.getsize(args.out),
        "format": "MPQ v1",
        "compression": "zlib",
        "built_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "dbc_files": 0,
        "load_order": LOAD_ORDER,
        "sources": [
            f"Data/{SOURCE_ARCHIVE}: {name} (sha256 {digest})" for name, digest in sorted(files.items())
        ],
        "entries": manifest_entries,
    }
    with open(args.manifest, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print(f"{args.out}: {len(files)} files, {manifest['size']} bytes, sha256 {manifest['sha256']}")
    print(f"{args.manifest}: written")


def check(args):
    with open(args.manifest, encoding="utf-8") as f:
        manifest = json.load(f)
    if sha256(args.out) != manifest["sha256"]:
        sys.exit(f"{args.out}: hash differs from {args.manifest}")
    if manifest.get("schema") != 1 or manifest.get("dbc_files") != 0:
        sys.exit(f"{args.manifest}: not a schema 1, dbc_files 0 manifest")
    folder = tempfile.mkdtemp(prefix="white-boss-models-check-")
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
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--client-data", default="~/Games/wotlk-clean/Data")
    parser.add_argument("--out", default=os.path.join(HERE, "dist", "patch-Y.MPQ"))
    parser.add_argument("--manifest", default=os.path.join(HERE, "manifest.json"))
    parser.add_argument("--check", action="store_true", help="verify an existing archive and manifest")
    args = parser.parse_args()
    if args.check:
        check(args)
    else:
        build(args)


if __name__ == "__main__":
    main()
