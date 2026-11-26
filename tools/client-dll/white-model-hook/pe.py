"""Shared PE helpers for the white-model-hook checks. Read-only."""

import hashlib
import struct
import sys

import os

EXE = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Games/wotlk-clean/Wow.exe")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


class Pe:
    def __init__(self, path=EXE):
        self.path = path
        self.d = open(path, "rb").read()
        self.sha256 = sha256(path)
        d = self.d
        e = struct.unpack_from("<I", d, 0x3C)[0]
        self.base = struct.unpack_from("<I", d, e + 24 + 28)[0]
        nsec = struct.unpack_from("<H", d, e + 6)[0]
        optsize = struct.unpack_from("<H", d, e + 20)[0]
        sect = e + 24 + optsize
        self.sections = []
        for i in range(nsec):
            s = sect + i * 40
            name = d[s:s + 8].rstrip(b"\0").decode()
            vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", d, s + 8)
            self.sections.append((name, va, vsize, rawptr, rawsize))

    def off2va(self, off):
        for _n, va, vsize, rawptr, rawsize in self.sections:
            if rawptr <= off < rawptr + rawsize:
                return self.base + va + (off - rawptr)
        return None

    def va2off(self, va):
        rva = va - self.base
        for _n, va_s, vsize, rawptr, rawsize in self.sections:
            if va_s <= rva < va_s + max(vsize, rawsize):
                return rawptr + (rva - va_s)
        return None

    def at(self, va, n):
        o = self.va2off(va)
        return self.d[o:o + n]

    def find(self, needle):
        out = []
        start = 0
        while True:
            i = self.d.find(needle, start)
            if i < 0:
                return out
            out.append(i)
            start = i + 1


if __name__ == "__main__":
    pe = Pe()
    print(f"exe {pe.path}")
    print(f"sha256 {pe.sha256}")
    print(f"image base 0x{pe.base:08x}")
    for name, va, vsize, rawptr, rawsize in pe.sections:
        print(f"  {name:9s} va 0x{va:08x} vsize 0x{vsize:x} raw 0x{rawptr:x} size 0x{rawsize:x}")
    print()
    for va in (0x00597700, 0x0084F280, 0x0084DF20):
        print(f"{va:08x}: {pe.at(va, 32).hex(' ')}")
