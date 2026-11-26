"""Verify the built proxy offline.

Checks, in order:
  1. every Divx export is a loader forwarder to DivxDecoder_orig.dll (never a null function);
  2. only KERNEL32 is imported (no CRT, no runtime dependencies);
  3. in a probe build, every stub has one counter increment and one indirect jump.

The exact replay bytes are checked by check_anchor.py, which assembles hook.S and compares it to the
image. This file checks structure, not instruction encoding.
"""

import struct
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "dist/DivxDecoder.dll"
d = open(path, "rb").read()

e = struct.unpack_from("<I", d, 0x3C)[0]
nsec, = struct.unpack_from("<H", d, e + 6)
optsize, = struct.unpack_from("<H", d, e + 20)
opt = e + 24
base, = struct.unpack_from("<I", d, opt + 28)
sect = opt + optsize
secs = []
for i in range(nsec):
    s = sect + i * 40
    name = d[s:s + 8].rstrip(b"\0").decode()
    vs, va, rs, rp = struct.unpack_from("<IIII", d, s + 8)
    secs.append((name, va, vs, rp, rs))


def rva2off(rva):
    for _n, va, vs, rp, rs in secs:
        if va <= rva < va + max(vs, rs):
            return rp + (rva - va)
    return None


def cstr(rva):
    o = rva2off(rva)
    return d[o:d.index(b"\0", o)].decode("latin1")


dd = opt + 96
erva, esize = struct.unpack_from("<II", d, dd)
idir, = struct.unpack_from("<I", d, dd + 8)
fail = 0

print(f"{path}: {len(d)} bytes, base 0x{base:x}, sections "
      + ", ".join(f"{n}@0x{v:x}" for n, v, _s, _r, _z in secs))

want = {"InitializeDivxDecoder", "UnInitializeDivxDecoder", "DivxDecode", "SetOutputFormat"}
if not erva:
    print("FAIL: no export directory")
    sys.exit(1)

eo = rva2off(erva)
nnames, = struct.unpack_from("<I", d, eo + 24)
nrva, = struct.unpack_from("<I", d, eo + 32)
eaddr, = struct.unpack_from("<I", d, eo + 28)
ordrva, = struct.unpack_from("<I", d, eo + 36)
found = {}
for i in range(nnames):
    no = rva2off(struct.unpack_from("<I", d, rva2off(nrva) + i * 4)[0])
    name = d[no:d.index(b"\0", no)].decode()
    ordi = struct.unpack_from("<H", d, rva2off(ordrva) + i * 2)[0]
    frva = struct.unpack_from("<I", d, rva2off(eaddr) + ordi * 4)[0]
    if erva <= frva < erva + esize:
        found[name] = cstr(frva)
    else:
        found[name] = f"CODE@{frva:x}"

print("exports:")
for name in sorted(found):
    target = found[name]
    ok = target.startswith("DivxDecoder_orig.")
    if not ok:
        fail += 1
    print(f"  {'OK ' if ok else 'BAD'} {name:26s} -> {target}")

missing = want - set(found)
if missing:
    fail += 1
    print(f"FAIL: missing exports {sorted(missing)}")

print("imports:")
if idir:
    o = rva2off(idir)
    while True:
        _ilt, _ts, _fc, name_rva, _iat = struct.unpack_from("<IIIII", d, o)
        if not name_rva:
            break
        dll = cstr(name_rva)
        print(f"  {dll}")
        if dll.lower() != "kernel32.dll":
            fail += 1
            print("  FAIL: unexpected import")
        o += 20
else:
    print("  none")

# Detour build check: every stub must start with `lock incl` (f0 ff 05) and end with an
# indirect jmp (ff 25). Only meaningful in the probe build, which contains the stubs.
text = next((s for s in secs if s[0] == ".text"), None)
if text:
    name, va, vs, rp, rs = text
    blob = d[rp:rp + rs]
    stubs = blob.count(bytes([0xF0, 0xFF, 0x05]))
    jmps = blob.count(bytes([0xFF, 0x25]))
    if stubs or jmps:
        print(f"probe stubs: {stubs} counter increments, {jmps} indirect jumps")
        if stubs != jmps:
            fail += 1
            print("  FAIL: stub count and jump count differ")

print()
if fail:
    print(f"FAILURES: {fail}")
    sys.exit(1)
print("OK: all exports are loader forwarders, only KERNEL32 imported.")
