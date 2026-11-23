"""StormLib ctypes wrapper for World of Warcraft 3.3.5a MPQ archives.

The client reads MPQs from its ``Data`` tree. This module wraps the parts of
StormLib the project needs: open/list/read/extract, create/add, verify, and
English-client load-order resolution (``find_highest``).

StormLib is expected from Homebrew on macOS::

    brew install stormlib
    export STORMLIB=/opt/homebrew/lib/libstorm.dylib

Only MPQ v1 with zlib is written. Callers that edit client data must start
from the highest-priority existing file; see ``decisions/ADR-027``.
"""

from __future__ import annotations

import ctypes
import hashlib
import os
import re
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator

# --- StormLib constants ---------------------------------------------------------------------

MPQ_OPEN_READ_ONLY = 0x00000100
MPQ_OPEN_NO_LISTFILE = 0x00010000
MPQ_OPEN_NO_ATTRIBUTES = 0x00020000

MPQ_CREATE_LISTFILE = 0x00100000
MPQ_CREATE_ATTRIBUTES = 0x00200000
MPQ_CREATE_ARCHIVE_V1 = 0x00000000
MPQ_CREATE_ARCHIVE_V2 = 0x01000000

MPQ_FILE_COMPRESS = 0x00000200
MPQ_FILE_REPLACEEXISTING = 0x80000000
MPQ_FILE_DELETE_MARKER = 0x02000000

MPQ_COMPRESSION_NONE = 0x00
MPQ_COMPRESSION_ZLIB = 0x02

SFILE_OPEN_FROM_MPQ = 0x00000000
SFILE_VERIFY_ALL = 0x0000000F

VERIFY_ERRORS = 0x0001 | 0x0002 | 0x0008 | 0x0020 | 0x0080 | 0x0200
VERIFY_HAS_CRC = 0x0010
VERIFY_HAS_MD5 = 0x0040
VERIFY_HAS_RAW_MD5 = 0x0100

INTERNAL_FILES = ("(listfile)", "(attributes)", "(signature)")

DEFAULT_STORMLIB_PATHS = (
    "/opt/homebrew/lib/libstorm.dylib",
    "/opt/homebrew/opt/stormlib/lib/libstorm.dylib",
    "/usr/local/lib/libstorm.dylib",
    "libstorm.dylib",
    "libstorm.so.5",
    "libstorm.so",
)


class MpqError(RuntimeError):
    """A StormLib call failed."""


def stormlib_path() -> str:
    """Return the StormLib path to load, honouring ``STORMLIB``."""
    override = os.environ.get("STORMLIB")
    if override:
        return override
    for candidate in DEFAULT_STORMLIB_PATHS:
        if os.path.isabs(candidate):
            if os.path.exists(candidate):
                return candidate
        else:
            return candidate
    return DEFAULT_STORMLIB_PATHS[0]


def stormlib_available() -> bool:
    try:
        _lib()
    except OSError:
        return False
    return True


class _FindData(ctypes.Structure):
    _fields_ = [
        ("cFileName", ctypes.c_char * 1024),
        ("szPlainName", ctypes.c_char_p),
        ("dwHashIndex", ctypes.c_uint),
        ("dwBlockIndex", ctypes.c_uint),
        ("dwFileSize", ctypes.c_uint),
        ("dwFileFlags", ctypes.c_uint),
        ("dwCompSize", ctypes.c_uint),
        ("dwFileTimeLo", ctypes.c_uint),
        ("dwFileTimeHi", ctypes.c_uint),
        ("lcLocale", ctypes.c_uint),
    ]


_LIB = None


def _lib():
    global _LIB
    if _LIB is None:
        lib = ctypes.CDLL(stormlib_path())
        handle = ctypes.c_void_p
        lib.SFileOpenArchive.argtypes = [
            ctypes.c_char_p,
            ctypes.c_uint,
            ctypes.c_uint,
            ctypes.POINTER(handle),
        ]
        lib.SFileOpenArchive.restype = ctypes.c_bool
        lib.SFileCreateArchive.argtypes = [
            ctypes.c_char_p,
            ctypes.c_uint,
            ctypes.c_uint,
            ctypes.POINTER(handle),
        ]
        lib.SFileCreateArchive.restype = ctypes.c_bool
        lib.SFileCloseArchive.argtypes = [handle]
        lib.SFileCloseArchive.restype = ctypes.c_bool
        lib.SFileHasFile.argtypes = [handle, ctypes.c_char_p]
        lib.SFileHasFile.restype = ctypes.c_bool
        lib.SFileOpenFileEx.argtypes = [
            handle,
            ctypes.c_char_p,
            ctypes.c_uint,
            ctypes.POINTER(handle),
        ]
        lib.SFileOpenFileEx.restype = ctypes.c_bool
        lib.SFileReadFile.argtypes = [
            handle,
            ctypes.c_void_p,
            ctypes.c_uint,
            ctypes.POINTER(ctypes.c_uint),
            ctypes.c_void_p,
        ]
        lib.SFileReadFile.restype = ctypes.c_bool
        lib.SFileCloseFile.argtypes = [handle]
        lib.SFileCloseFile.restype = ctypes.c_bool
        lib.SFileGetFileSize.argtypes = [handle, ctypes.POINTER(ctypes.c_uint)]
        lib.SFileGetFileSize.restype = ctypes.c_uint
        lib.SFileExtractFile.argtypes = [
            handle,
            ctypes.c_char_p,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        lib.SFileExtractFile.restype = ctypes.c_bool
        lib.SFileAddFileEx.argtypes = [
            handle,
            ctypes.c_char_p,
            ctypes.c_char_p,
            ctypes.c_uint,
            ctypes.c_uint,
            ctypes.c_uint,
        ]
        lib.SFileAddFileEx.restype = ctypes.c_bool
        lib.SFileFindFirstFile.argtypes = [
            handle,
            ctypes.c_char_p,
            ctypes.POINTER(_FindData),
            ctypes.c_char_p,
        ]
        lib.SFileFindFirstFile.restype = handle
        lib.SFileFindNextFile.argtypes = [handle, ctypes.POINTER(_FindData)]
        lib.SFileFindNextFile.restype = ctypes.c_bool
        lib.SFileFindClose.argtypes = [handle]
        lib.SFileFindClose.restype = ctypes.c_bool
        lib.SFileVerifyFile.argtypes = [handle, ctypes.c_char_p, ctypes.c_uint]
        lib.SFileVerifyFile.restype = ctypes.c_uint
        lib.SErrGetLastError.argtypes = []
        lib.SErrGetLastError.restype = ctypes.c_uint
        _LIB = lib
    return _LIB


def _error_code() -> int:
    try:
        return int(_lib().SErrGetLastError())
    except OSError:
        return 0


def _fail(action: str, name: str | None = None) -> MpqError:
    code = _error_code()
    where = f" ({name})" if name else ""
    return MpqError(f"{action} failed{where}: StormLib error {code}")


# --- paths -----------------------------------------------------------------------------------


def normalize_archive_path(name: str) -> str:
    """Normalise a client path and reject absolute or traversal paths.

    MPQ names use backslashes. The returned path always uses backslashes and
    has no empty or ``.`` components.
    """
    if not isinstance(name, str) or not name:
        raise ValueError("empty archive path")
    if "\x00" in name:
        raise ValueError("archive path contains NUL")
    text = name.replace("\\", "/").strip()
    if not text or text.startswith("/"):
        raise ValueError(f"absolute archive path: {name!r}")
    if re.match(r"^[A-Za-z]:", text):
        raise ValueError(f"drive-qualified archive path: {name!r}")
    parts = [part for part in text.split("/") if part not in ("", ".")]
    if not parts or any(part == ".." for part in parts):
        raise ValueError(f"unsafe archive path: {name!r}")
    return "\\".join(parts)


def normalize_local_path(path: str | Path) -> Path:
    return Path(path).expanduser()


def safe_destination(root: str | Path, archive_name: str) -> Path:
    """Resolve an archive name below ``root`` and reject escapes."""
    root_path = Path(root).expanduser().resolve()
    normalized = normalize_archive_path(archive_name)
    destination = (root_path / Path(*normalized.split("\\"))).resolve()
    if destination != root_path and root_path not in destination.parents:
        raise ValueError(f"archive path escapes destination: {archive_name!r}")
    return destination


# --- hashing ---------------------------------------------------------------------------------


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: str | Path, chunk_size: int = 1 << 20) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def read_header(path: str | Path) -> dict:
    """Read the small amount of MPQ header data ``inspect`` reports.

    Supports the standard ``MPQ\\x1a`` header. User-data headers
    (``MPQ\\x1b``) return ``unknown``; StormLib still opens them.
    """
    path = Path(path)
    with open(path, "rb") as handle:
        head = handle.read(32)
    if len(head) < 16:
        raise MpqError(f"{path}: file is too short to be an MPQ")
    magic, header_size = struct.unpack_from("<4sI", head, 0)
    if magic != b"MPQ\x1a":
        return {
            "magic": magic.decode("latin-1", "replace"),
            "header_size": header_size,
            "format_version": None,
            "archive_size": int(path.stat().st_size),
            "user_data": magic == b"MPQ\x1b",
        }
    version, sector_shift = struct.unpack_from("<HH", head, 12)
    archive_size = struct.unpack_from("<I", head, 8)[0]
    return {
        "magic": magic.decode("latin-1", "replace"),
        "header_size": header_size,
        "format_version": version,
        "sector_size": 512 << sector_shift,
        "archive_size": archive_size,
        "user_data": False,
    }


# --- entries ---------------------------------------------------------------------------------


@dataclass(frozen=True)
class MpqEntry:
    name: str
    size: int
    compressed_size: int
    flags: int
    locale: int = 0

    @property
    def is_internal(self) -> bool:
        return self.name.lower() in {item.lower() for item in INTERNAL_FILES}


@dataclass(frozen=True)
class VerifyResult:
    name: str
    flags: int

    @property
    def ok(self) -> bool:
        return (self.flags & VERIFY_ERRORS) == 0


@dataclass(frozen=True)
class WhichResult:
    path: str
    winner: Path | None
    sources: tuple[Path, ...]
    skipped: tuple[Path, ...] = ()


class Archive:
    """A StormLib archive handle."""

    def __init__(self, path: str | Path, flags: int = MPQ_OPEN_READ_ONLY, handle=None):
        self.path = Path(path).expanduser().resolve()
        self._handle = handle
        self._closed = False
        if handle is None:
            self.open(flags)

    def open(self, flags: int = MPQ_OPEN_READ_ONLY) -> None:
        handle = ctypes.c_void_p()
        if not _lib().SFileOpenArchive(
            str(self.path).encode(), 0, flags, ctypes.byref(handle)
        ):
            raise _fail("open archive", str(self.path))
        self._handle = handle

    @classmethod
    def create(
        cls,
        path: str | Path,
        max_files: int = 16,
        flags: int = MPQ_CREATE_LISTFILE | MPQ_CREATE_ATTRIBUTES | MPQ_CREATE_ARCHIVE_V1,
    ) -> "Archive":
        path = Path(path).expanduser().resolve()
        path.parent.mkdir(parents=True, exist_ok=True)
        handle = ctypes.c_void_p()
        if not _lib().SFileCreateArchive(
            str(path).encode(), flags, max(1, max_files), ctypes.byref(handle)
        ):
            raise _fail("create archive", str(path))
        return cls(path, handle=handle)

    def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        if self._handle:
            _lib().SFileCloseArchive(self._handle)
            self._handle = None

    def __enter__(self) -> "Archive":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    @property
    def handle(self):
        if self._closed or not self._handle:
            raise MpqError("archive is closed")
        return self._handle

    def has_file(self, name: str) -> bool:
        normalized = normalize_archive_path(name)
        return bool(_lib().SFileHasFile(self.handle, normalized.encode()))

    def list_files(self, mask: str = "*", include_internal: bool = False) -> list[MpqEntry]:
        found = _FindData()
        search = _lib().SFileFindFirstFile(
            self.handle, mask.encode(), ctypes.byref(found), None
        )
        if not search:
            if mask == "*" and self.has_file("(listfile)"):
                return self._list_from_listfile(include_internal)
            return []
        entries: list[MpqEntry] = []
        try:
            while True:
                name = found.cFileName.decode("latin-1")
                if include_internal or name.lower() not in {
                    item.lower() for item in INTERNAL_FILES
                }:
                    entries.append(
                        MpqEntry(
                            name=name,
                            size=found.dwFileSize,
                            compressed_size=found.dwCompSize,
                            flags=found.dwFileFlags,
                            locale=found.lcLocale,
                        )
                    )
                if not _lib().SFileFindNextFile(search, ctypes.byref(found)):
                    break
        finally:
            _lib().SFileFindClose(search)
        return entries

    def _list_from_listfile(self, include_internal: bool) -> list[MpqEntry]:
        names = self.listfile()
        entries = []
        for name in names:
            if not include_internal and name.lower() in {
                item.lower() for item in INTERNAL_FILES
            }:
                continue
            if not self.has_file(name):
                continue
            entries.append(
                MpqEntry(
                    name=name,
                    size=self.get_file_size(name),
                    compressed_size=0,
                    flags=0,
                )
            )
        return entries

    def listfile(self) -> list[str]:
        data = self.read_file("(listfile)")
        text = data.decode("latin-1")
        return [
            line.strip().replace("/", "\\")
            for line in text.splitlines()
            if line.strip()
        ]

    def attributes(self) -> bytes | None:
        if not self.has_file("(attributes)"):
            return None
        return self.read_file("(attributes)")

    def get_file_size(self, name: str) -> int:
        normalized = normalize_archive_path(name)
        handle = ctypes.c_void_p()
        if not _lib().SFileOpenFileEx(
            self.handle, normalized.encode(), SFILE_OPEN_FROM_MPQ, ctypes.byref(handle)
        ):
            raise _fail("open file", normalized)
        try:
            high = ctypes.c_uint()
            low = _lib().SFileGetFileSize(handle, ctypes.byref(high))
            if low == 0xFFFFFFFF:
                raise _fail("read file size", normalized)
            return (int(high.value) << 32) | int(low)
        finally:
            _lib().SFileCloseFile(handle)

    def iter_file(self, name: str, chunk_size: int = 1 << 20) -> Iterator[bytes]:
        normalized = normalize_archive_path(name)
        archive_handle = self.handle
        handle = ctypes.c_void_p()
        if not _lib().SFileOpenFileEx(
            archive_handle,
            normalized.encode(),
            SFILE_OPEN_FROM_MPQ,
            ctypes.byref(handle),
        ):
            raise _fail("open file", normalized)
        try:
            high = ctypes.c_uint()
            size = _lib().SFileGetFileSize(handle, ctypes.byref(high))
            if size == 0xFFFFFFFF:
                raise _fail("read file size", normalized)
            remaining = (int(high.value) << 32) | int(size)
            while remaining > 0:
                chunk = min(chunk_size, remaining)
                buffer = ctypes.create_string_buffer(chunk)
                read = ctypes.c_uint(0)
                if not _lib().SFileReadFile(
                    handle, buffer, chunk, ctypes.byref(read), None
                ):
                    raise _fail("read file", normalized)
                if read.value == 0:
                    raise MpqError(f"read file ({normalized}) returned no data")
                yield buffer.raw[: read.value]
                remaining -= read.value
        finally:
            _lib().SFileCloseFile(handle)

    def read_file(self, name: str) -> bytes:
        return b"".join(self.iter_file(name))

    def sha256(self, name: str) -> str:
        digest = hashlib.sha256()
        for chunk in self.iter_file(name):
            digest.update(chunk)
        return digest.hexdigest()

    def extract(self, name: str, destination: str | Path) -> Path:
        """Extract one file below ``destination`` with traversal checks."""
        normalized = normalize_archive_path(name)
        target_root = Path(destination).expanduser()
        target = safe_destination(target_root, normalized)
        target.parent.mkdir(parents=True, exist_ok=True)
        if not _lib().SFileExtractFile(
            self.handle, normalized.encode(), str(target).encode(), 0
        ):
            raise _fail("extract file", normalized)
        return target

    def extract_all(self, destination: str | Path) -> list[Path]:
        extracted = []
        for entry in self.list_files():
            extracted.append(self.extract(entry.name, destination))
        return extracted

    def add_file(
        self,
        source: str | Path,
        archive_name: str,
        compression: int = MPQ_COMPRESSION_ZLIB,
    ) -> None:
        normalized = normalize_archive_path(archive_name)
        source_path = Path(source).expanduser().resolve()
        if not source_path.is_file():
            raise MpqError(f"source file not found: {source_path}")
        flags = MPQ_FILE_REPLACEEXISTING
        if compression != MPQ_COMPRESSION_NONE:
            flags |= MPQ_FILE_COMPRESS
        if not _lib().SFileAddFileEx(
            self.handle,
            str(source_path).encode(),
            normalized.encode(),
            flags,
            compression,
            compression,
        ):
            raise _fail("add file", normalized)

    def add_directory(self, root: str | Path, prefix: str = "") -> list[str]:
        root_path = Path(root).expanduser().resolve()
        if not root_path.is_dir():
            raise MpqError(f"source directory not found: {root_path}")
        added = []
        for source in sorted(path for path in root_path.rglob("*") if path.is_file()):
            relative = source.relative_to(root_path).as_posix().replace("/", "\\")
            archive_name = f"{normalize_archive_path(prefix)}\\{relative}" if prefix else relative
            self.add_file(source, archive_name)
            added.append(archive_name)
        return added

    def verify_file(self, name: str) -> VerifyResult:
        normalized = normalize_archive_path(name)
        flags = int(_lib().SFileVerifyFile(self.handle, normalized.encode(), SFILE_VERIFY_ALL))
        return VerifyResult(normalized, flags)

    def inspect(self) -> dict:
        header = read_header(self.path)
        entries = self.list_files(include_internal=True)
        names = {entry.name.lower() for entry in entries}
        return {
            "path": str(self.path),
            "sha256": sha256_file(self.path),
            "size": self.path.stat().st_size,
            "header": header,
            "format": (
                f"MPQ v{header['format_version'] + 1}"
                if header.get("format_version") is not None
                else "unknown"
            ),
            "listfile": "(listfile)" in names,
            "attributes": "(attributes)" in names,
            "signature": "(signature)" in names,
            "files": len([e for e in entries if not e.is_internal]),
            "uncompressed_size": sum(e.size for e in entries if not e.is_internal),
            "compressed_size": sum(e.compressed_size for e in entries if not e.is_internal),
            "entries": entries,
        }


# --- client load order ----------------------------------------------------------------------

_LOCALE_BASE = (
    "backup-{locale}.MPQ",
    "base-{locale}.MPQ",
    "locale-{locale}.MPQ",
    "expansion-locale-{locale}.MPQ",
    "expansion-speech-{locale}.MPQ",
    "lichking-locale-{locale}.MPQ",
    "lichking-speech-{locale}.MPQ",
    "speech-{locale}.MPQ",
)


def _base_names() -> list[str]:
    names = ["common.MPQ", "common-2.MPQ", "expansion.MPQ", "lichking.MPQ"]
    names += ["patch.MPQ"] + [f"patch-{number}.MPQ" for number in range(2, 10)]
    names += [f"patch-{letter}.MPQ" for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ"]
    return names


def _locale_names(locale: str) -> tuple[list[str], list[str], list[str]]:
    nonpatch = [name.format(locale=locale) for name in _LOCALE_BASE]
    numeric = [f"patch-{locale}.MPQ"] + [
        f"patch-{locale}-{number}.MPQ" for number in range(2, 10)
    ]
    alpha = [f"patch-{locale}-{letter}.MPQ" for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ"]
    return nonpatch, numeric, alpha


def _case_insensitive_lookup(directory: Path) -> dict[str, Path]:
    if not directory.is_dir():
        return {}
    return {path.name.lower(): path for path in directory.iterdir() if path.is_file()}


def archive_chain(
    data_dir: str | Path,
    locale: str = "enUS",
    order: str = "english",
) -> list[Path]:
    """Return existing archives from lowest to highest priority.

    ``order="english"`` follows the 3.3.5 English client: locale archives load
    first, then base archives, then base numeric and alphabetic patches.
    ``order="localized"`` is the Russian/Chinese shape, where locale patches
    load last. The project targets the English client.
    """
    data_path = Path(data_dir).expanduser()
    locale_path = data_path / locale
    locale_files = _case_insensitive_lookup(locale_path)
    data_files = _case_insensitive_lookup(data_path)

    base = _base_names()
    locale_nonpatch, locale_numeric, locale_alpha = _locale_names(locale)

    def pick(names: Iterable[str], table: dict[str, Path]) -> list[Path]:
        found = []
        for name in names:
            path = table.get(name.lower())
            if path is not None:
                found.append(path)
        return found

    base_nonpatch = base[:4]
    base_numeric = base[4:13]
    base_alpha = base[13:]

    groups = {
        "locale_nonpatch": pick(locale_nonpatch, locale_files),
        "locale_numeric": pick(locale_numeric, locale_files),
        "locale_alpha": pick(locale_alpha, locale_files),
        "base_nonpatch": pick(base_nonpatch, data_files),
        "base_numeric": pick(base_numeric, data_files),
        "base_alpha": pick(base_alpha, data_files),
    }
    if order == "english":
        sequence = (
            "locale_nonpatch",
            "locale_numeric",
            "locale_alpha",
            "base_nonpatch",
            "base_numeric",
            "base_alpha",
        )
    elif order == "localized":
        sequence = (
            "base_nonpatch",
            "base_numeric",
            "base_alpha",
            "locale_nonpatch",
            "locale_numeric",
            "locale_alpha",
        )
    else:
        raise ValueError(f"unknown load order: {order!r}")
    return [path for group in sequence for path in groups[group]]


def find_highest(
    data_dir: str | Path,
    name: str,
    locale: str = "enUS",
    order: str = "english",
) -> WhichResult:
    """Find the archive the client would use for ``name``.

    Opens archives from highest to lowest priority. Unreadable archives are
    reported in ``skipped`` rather than failing the whole lookup, because some
    third-party patches are encrypted.
    """
    normalized = normalize_archive_path(name)
    chain = archive_chain(data_dir, locale=locale, order=order)
    sources: list[Path] = []
    skipped: list[Path] = []
    for archive_path in reversed(chain):
        try:
            with Archive(archive_path) as archive:
                if archive.has_file(normalized):
                    sources.append(archive_path)
        except (MpqError, OSError):
            skipped.append(archive_path)
    winner = sources[0] if sources else None
    sources_low_to_high = tuple(reversed(sources))
    return WhichResult(normalized, winner, sources_low_to_high, tuple(reversed(skipped)))
