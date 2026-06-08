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
# DATA_LOC: where this app's data starts (code is #4000.. below it, data ..#7FFF
# above). The default 0x6200 is a 50/50 split; a code-heavy/data-light app (NOTEPAD)
# can pass a higher value to trade its spare data room for code room. Per-app so a
# data-heavy app (VIEWER) keeps the low split. (#97)
DATA_LOC="${DATA_LOC:-0x6200}"

SDCC="${SDCC:-sdcc}"
BIN="$(dirname "$(command -v "$SDCC")")"   # sdasz80 / makebin sit beside sdcc
SDAS="$BIN/sdasz80"
MAKEBIN="$BIN/makebin"

work="build/$(basename "$APP")"
mkdir -p "$work"

"$SDAS" -o "$work/crt0.rel"  "$GB/crt0.s"
"$SDAS" -o "$work/gblib.rel" "$GB/gblib.s"
# --fomit-frame-pointer: frame on IY, not IX. The kernel/fs code uses IX as a
# scratch (it never touches IY) and firmware calls preserve the caller's IY, so
# this stops a kernel call from wrecking an app's frame pointer (which crashed
# the notepad's return - SDCC's epilogue is `ld sp,<fp>`).
"$SDCC" -mz80 --fomit-frame-pointer -I "$GB" -c "$APP/main.c" -o "$work/main.rel"
"$SDCC" -mz80 --fomit-frame-pointer -I "$GB" -c "$GB/gbwin.c" -o "$work/gbwin.rel"
"$SDCC" -mz80 --no-std-crt0 --code-loc 0x4000 --data-loc "$DATA_LOC" \
    "$work/crt0.rel" "$work/main.rel" "$work/gbwin.rel" "$work/gblib.rel" -o "$work/app.ihx"
# STABILITY GUARD: the app must fit its 16K page - code below its data-loc, data+bss
# below the kernel (#8000). A silent overflow corrupts memory at runtime (it bit
# NOTEPAD once); turn it into a loud build failure here.
python3 - "$work/app.map" "$APP" "$DATA_LOC" <<'PY'
import sys, re
mapf, app, dloc = sys.argv[1], sys.argv[2], int(sys.argv[3], 16)
area = {}
for line in open(mapf):
    m = re.match(r'^(_CODE|_DATA|_BSS|_INITIALIZED|_GSINIT)\s+([0-9A-Fa-f]{8})\s+([0-9A-Fa-f]{8})', line)
    if m:
        area[m.group(1)] = (int(m.group(2), 16), int(m.group(3), 16))
code_end = sum(area.get('_CODE', (0, 0)))
top = max((s + sz) for s, sz in area.values()) if area else 0
errs = []
if code_end > dloc:  errs.append('code ends 0x%04X > data-loc 0x%04X' % (code_end, dloc))
if top > 0x8000:     errs.append('data/bss ends 0x%04X > kernel 0x8000' % top)
if errs:
    sys.stderr.write('FIT ERROR (%s): %s - shrink it or raise DATA_LOC\n' % (app, '; '.join(errs)))
    sys.exit(1)
PY

"$MAKEBIN" -p "$work/app.ihx" "$work/app.bin"

# makebin emits a flat image from #0000; the app lives at #4000 -> strip low 16K.
tail -c +16385 "$work/app.bin" > "$OUT"
echo "Built $OUT ($(stat -c%s "$OUT") bytes) from $APP"
