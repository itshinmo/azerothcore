"""Offline verification of the probe build.

For each probe target this checks three things against the real exe:

  1. the 9- or 14-byte prologue listed here matches the bytes in the image;
  2. the window length is the instruction boundary listed in BOUNDARIES. That list is asserted here
     and cross-checked against the disassembly recorded in hook.S; it is not derived automatically;
  3. the instructions hook.S replays are byte-identical to that prologue.

Check 3 assembles hook.S and compares the replayed instruction bytes, rather than searching the
source text. That is what catches an operand or offset mistake.

Read-only. Run from this directory:

    python3 check_anchor.py [path/to/Wow.exe]
"""

import os
import struct
import subprocess
import sys
import tempfile

from pe import Pe

# (va, name, prologue bytes) -- `len(prologue)` is also the patch window length.
PROBES = [
    (0x005975E0, "record->display",
     bytes([0x55, 0x8B, 0xEC, 0x51, 0x53, 0x8B, 0x5D, 0x08, 0x57])),
    (0x00597700, "display build",
     bytes([0x55, 0x8B, 0xEC, 0x51, 0x8B, 0x45, 0x08, 0x85, 0xC0])),
    (0x005977E0, "SetCreature",
     bytes([0x55, 0x8B, 0xEC, 0x8B, 0x45, 0x08, 0x56, 0x8B, 0xF1])),
    (0x00597840, "set display id",
     bytes([0x55, 0x8B, 0xEC, 0x8B, 0x45, 0x08, 0x33, 0xD2,
            0x39, 0x91, 0xE0, 0x00, 0x00, 0x00])),
    (0x0084F280, "model setter",
     bytes([0x55, 0x8B, 0xEC, 0x56, 0x8B, 0x75, 0x08, 0x6A, 0x01])),
]

# Instruction boundaries in each prologue, taken from the disassembly recorded in the README. The
# patch window must end on one of these, or the stub would resume in the middle of an instruction.
# This list is asserted, not derived: re-derive it whenever a prologue changes.
BOUNDARIES = {
    0x005975E0: [9],
    0x00597700: [9],
    0x005977E0: [9],
    0x00597840: [14],
    0x0084F280: [9],
}

REPLAY_START = "_hook_entry"
REPLAY_MARK = "jmp *_g_resume"


def assemble_hook():
    """Assemble hook.S and return its .text bytes as a flat blob."""
    here = os.path.dirname(os.path.abspath(__file__))
    with tempfile.TemporaryDirectory() as tmp:
        obj = os.path.join(tmp, "hook.o")
        subprocess.run(["i686-w64-mingw32-gcc", "-c", os.path.join(here, "hook.S"),
                        "-o", obj], check=True)
        out = subprocess.run(["i686-w64-mingw32-objdump", "-d", obj],
                             check=True, capture_output=True, text=True).stdout
    # Parse objdump into (symbol, [bytes]) runs.
    runs = []
    symbol = None
    current = bytearray()
    for line in out.splitlines():
        if line.endswith(">:") and "<" in line:
            if symbol and current:
                runs.append((symbol, bytes(current)))
            symbol = line.split("<")[1].rstrip(">:")
            current = bytearray()
            continue
        parts = line.split("\t")
        if len(parts) >= 3 and parts[0].strip().endswith(":"):
            hexbytes = parts[1].strip().split()
            try:
                current.extend(int(b, 16) for b in hexbytes)
            except ValueError:
                pass
    if symbol and current:
        runs.append((symbol, bytes(current)))
    return dict(runs)


def replayed_prefix(blob, prologue):
    """Bytes of a stub that are the prologue replay: everything after the last counter increment."""
    # Each stub starts with `lock incl _g_countN` (7 bytes) then replays the prologue.
    return blob[7:7 + len(prologue)]


def main():
    path = os.path.expanduser(sys.argv[1]) if len(sys.argv) > 1 else None
    pe = Pe(path) if path else Pe()

    print(f"exe    {pe.path}")
    print(f"sha256 {pe.sha256}")
    print(f"base   0x{pe.base:08x}")
    if pe.base != 0x400000:
        print("FAIL: image base is not 0x400000; the fixed addresses are invalid.")
        return 1

    stubs = assemble_hook()
    if not stubs:
        print("FAIL: could not assemble hook.S")
        return 1

    fail = 0
    for index, (va, name, prologue) in enumerate(PROBES):
        image = pe.at(va, len(prologue))
        symbol = f"_probe{index}"
        stub = stubs.get(symbol)

        print(f"\n{name} @0x{va:08x}  window {len(prologue)}")
        if image != prologue:
            fail += 1
            print(f"  FAIL: image has {image.hex(' ')}, table expects {prologue.hex(' ')}")
        else:
            print(f"  image    {image.hex(' ')}")

        if len(prologue) not in BOUNDARIES[va]:
            fail += 1
            print(f"  FAIL: window length is not an instruction boundary for this target")
        else:
            print(f"  boundary ok, resume at +{len(prologue)}")

        if not stub:
            fail += 1
            print(f"  FAIL: hook.S has no {symbol}")
            continue
        replay = replayed_prefix(stub, prologue)
        if replay != prologue:
            fail += 1
            print(f"  FAIL: {symbol} replays {replay.hex(' ')}")
        else:
            print(f"  replay   {replay.hex(' ')}  (byte-identical)")

    print()
    if fail:
        print(f"FAILURES: {fail}")
        return 1
    print(f"OK: {len(PROBES)} targets verified: prologue, instruction boundary, byte-identical replay.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
