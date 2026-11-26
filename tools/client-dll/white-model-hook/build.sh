#!/bin/sh
# Build the DivxDecoder proxy DLL (32-bit Windows PE, freestanding).
#
#   brew install mingw-w64
#   sh build.sh            # forwarding only
#   DETOUR=1 sh build.sh   # with probes
#
# Reproducibility: the PE timestamp, the image base and the build id are all pinned, so the same
# sources give the same bytes from any checkout path. Verify with `shasum -a 256 dist/DivxDecoder.dll`.
#
# -ffreestanding keeps GCC from lowering our own loops into calls to memset/memcpy, which a
# -nostdlib image cannot resolve. A hand-written shim is NOT safe here: at -O2 GCC recognises the
# pattern and rewrites the shim into a jump to itself, which hangs the client at load.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
CC=${CC:-i686-w64-mingw32-gcc}
DETOUR=${DETOUR:-0}

mkdir -p "$HERE/dist"

$CC \
    -std=c11 -O2 -ffreestanding -nostdlib -fno-builtin \
    -Wall -Wextra -Wno-unused-parameter \
    -DENABLE_DETOUR="$DETOUR" \
    -DBUILD_ID='"'"${BUILD_ID:-20261126}"'"' \
    -shared \
    -o "$HERE/dist/DivxDecoder.dll" \
    "$HERE/dllmain.c" "$HERE/hook.S" "$HERE/DivxDecoder.def" \
    -lkernel32 \
    -Wl,--entry,DllMain@12 \
    -Wl,--enable-stdcall-fixup \
    -Wl,--no-insert-timestamp \
    -Wl,--disable-auto-image-base \
    -Wl,--image-base,0x10000000

file "$HERE/dist/DivxDecoder.dll"
ls -l "$HERE/dist/DivxDecoder.dll"
