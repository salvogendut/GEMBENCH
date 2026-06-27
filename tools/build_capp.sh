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

APP="${1:-apps/clock}"
OUT="${2:-build/CLOCK.RAW}"
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
# Opt-in dialogs (#114, #142). The heavy render (popup/prompt/file-picker) now lives in
# the paged GBUI kernel module (#142 step 1b); an app that needs ANY dialog links only
# the tiny marshalling stub gbui_stub.c (gb_popup/gb_prompt/gb_pickfile/gb_pickdir ->
# GB_UI). That ~800-byte/app saving is what lets the data-heavy apps fit gb_doc.
#   DIALOGS / PROMPT / PICKER  -> gbui_stub.c (the stubs)
#   DOC=1                      -> gbdoc.c too (the document/File-menu framework)
DLG_REL=""
if [ "${DIALOGS:-0}" = "1" ] || [ "${PROMPT:-0}" = "1" ] || [ "${PICKER:-0}" = "1" ] || [ "${DOC:-0}" = "1" ] || [ "${DOCRO:-0}" = "1" ]; then
    "$SDCC" -mz80 --fomit-frame-pointer -I "$GB" -c "$GB/gbui_stub.c" -o "$work/gbui_stub.rel"
    DLG_REL="$work/gbui_stub.rel"
fi
# DOC=1 = the full document framework; DOCRO=1 = a READ-ONLY variant (-DGBDOC_RO) that
# omits the Save/Save As path, so a viewer-style app saves that code room (#144).
if [ "${DOC:-0}" = "1" ] || [ "${DOCRO:-0}" = "1" ]; then
    RO=""; [ "${DOCRO:-0}" = "1" ] && RO="-DGBDOC_RO"
    "$SDCC" -mz80 --fomit-frame-pointer $RO -I "$GB" -c "$GB/gbdoc.c" -o "$work/gbdoc.rel"
    DLG_REL="$DLG_REL $work/gbdoc.rel"
fi
# NET=1 -> gbnet_stub.c (gb_net_* -> the paged GBNET W5100 module, #238)
if [ "${NET:-0}" = "1" ]; then
    "$SDCC" -mz80 --fomit-frame-pointer -I "$GB" -c "$GB/gbnet_stub.c" -o "$work/gbnet_stub.rel"
    DLG_REL="$DLG_REL $work/gbnet_stub.rel"
fi
"$SDCC" -mz80 --no-std-crt0 --code-loc 0x4000 --data-loc "$DATA_LOC" \
    "$work/crt0.rel" "$work/main.rel" "$work/gbwin.rel" $DLG_REL "$work/gblib.rel" -o "$work/app.ihx"
# STABILITY GUARD: the app must fit its 16K page. The whole LOADED IMAGE
# (_CODE + the startup tails _GSINIT/_GSFINAL/_INITIALIZER, which the linker places
# AFTER the code) must end below data-loc - otherwise the RAM data area starts inside
# it and gsinit zeroes its own code as it runs -> instant reboot (bit NOTEPAD: a
# _CODE-only check passed while _GSINIT overlapped _DATA). And data+bss must end below
# the kernel (#8000). Turn either overflow into a loud build failure.
python3 - "$work/app.map" "$APP" "$DATA_LOC" <<'PY'
import sys, re
mapf, app, dloc = sys.argv[1], sys.argv[2], int(sys.argv[3], 16)
area = {}
for line in open(mapf):
    m = re.match(r'^(_CODE|_DATA|_BSS|_INITIALIZED|_GSINIT|_GSFINAL|_INITIALIZER)\s+([0-9A-Fa-f]{8})\s+([0-9A-Fa-f]{8})', line)
    if m:
        area[m.group(1)] = (int(m.group(2), 16), int(m.group(3), 16))
LOAD = ('_CODE', '_GSINIT', '_GSFINAL', '_INITIALIZER')   # the loaded image (before data-loc)
img_end = max((area[a][0] + area[a][1]) for a in LOAD if a in area)
top = max((s + sz) for s, sz in area.values()) if area else 0
errs = []
if img_end > dloc:  errs.append('loaded image ends 0x%04X > data-loc 0x%04X (gsinit/data overlap)' % (img_end, dloc))
if top > 0x8000:    errs.append('data/bss ends 0x%04X > kernel 0x8000' % top)
if errs:
    sys.stderr.write('FIT ERROR (%s): %s - shrink it or raise DATA_LOC\n' % (app, '; '.join(errs)))
    sys.exit(1)
PY

"$MAKEBIN" -p "$work/app.ihx" "$work/app.bin"

# makebin emits a flat image from #0000; the app lives at #4000 -> strip low 16K.
tail -c +16385 "$work/app.bin" > "$OUT"
echo "Built $OUT ($(stat -c%s "$OUT") bytes) from $APP"
