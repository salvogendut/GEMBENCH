#!/usr/bin/env bash
# Build a GEOBENCH C app with SDCC into a raw #4000 image - the same format as
# the RASM .RAW app binaries, so the kernel can incbin/package it identically.
#
# The C app is just apps/<name>/main.c; it reaches the kernel through the shared
# libgb (lib/gb/gblib.s + gb.h) and shared crt0 (lib/gb/crt0.s, the #4000 entry).
# Linked: crt0 FIRST (so _start is at #4000), then main, then the libgb trampolines.
#
#   tools/build_capp.sh [app_dir] [out.RAW]
#   tools/build_capp.sh apps/chello build/CHELLO.RAW   (defaults)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-apps/chello}"
OUT="${2:-build/CHELLO.RAW}"
GB="lib/gb"                                 # shared libgb (gb.h, gblib.s, crt0.s)

SDCC="${SDCC:-sdcc}"
BIN="$(dirname "$(command -v "$SDCC")")"   # sdasz80 / makebin sit beside sdcc
SDAS="$BIN/sdasz80"
MAKEBIN="$BIN/makebin"

work="build/$(basename "$APP")"
mkdir -p "$work"

"$SDAS" -o "$work/crt0.rel"  "$GB/crt0.s"
"$SDAS" -o "$work/gblib.rel" "$GB/gblib.s"
"$SDCC" -mz80 -I "$GB" -c "$APP/main.c" -o "$work/main.rel"
"$SDCC" -mz80 --no-std-crt0 --code-loc 0x4000 --data-loc 0x6000 \
    "$work/crt0.rel" "$work/main.rel" "$work/gblib.rel" -o "$work/app.ihx"
"$MAKEBIN" -p "$work/app.ihx" "$work/app.bin"

# makebin emits a flat image from #0000; the app lives at #4000 -> strip low 16K.
tail -c +16385 "$work/app.bin" > "$OUT"
echo "Built $OUT ($(stat -c%s "$OUT") bytes) from $APP"
