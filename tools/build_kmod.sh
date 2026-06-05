#!/usr/bin/env bash
# Build a GEOBENCH kernel C module (SDCC -mz80) and report its code size.
#
# Kernel modules are the SymbOS-style answer to "kernel in C": the resident asm
# nucleus (jump table, banking, hardware leaves) stays asm, and branchy *logic*
# moves into C modules that live in a paged bank and are called through the
# inter-bank trampoline. We measure code size because the resident region
# (#8000..~#A67B) is nearly full, so modules must be banked, not resident.
#
#   tools/build_kmod.sh kernel/kc/kcfg.c   -> build/kc/kcfg.rel + size report
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-kernel/kc/kcfg.c}"
SDCC="${SDCC:-sdcc}"
work="build/kc"
mkdir -p "$work"

base="$(basename "${SRC%.c}")"
rel="$work/$base.rel"

# --fomit-frame-pointer: frame on IY, matching the app build (the kernel uses IX
# as scratch). The module is pure logic -> expect _DATA/_INITIALIZER = 0.
"$SDCC" -mz80 --fomit-frame-pointer -I "$(dirname "$SRC")" -c "$SRC" -o "$rel"

code_hex="$(awk '/^A _CODE size/ {print $4; exit}' "$rel")"
data_hex="$(awk '/^A _DATA size/ {print $4; exit}' "$rel")"
init_hex="$(awk '/^A _INITIALIZER size/ {print $4; exit}' "$rel")"
printf 'built %s\n  _CODE        = %5d bytes (0x%s)\n  _DATA        = %5d bytes\n  _INITIALIZER = %5d bytes\n' \
    "$rel" "$((16#${code_hex:-0}))" "${code_hex:-0}" "$((16#${data_hex:-0}))" "$((16#${init_hex:-0}))"
