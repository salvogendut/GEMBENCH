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
GBLIB_SRC="${GBLIB_SRC:-$GB/gblib.s}"
APP_CFLAGS="${APP_CFLAGS:-}"
LOAD_LIMIT="${LOAD_LIMIT:-0x7F00}"
# DATA_LOC: where this app's data starts (code is #4000.. below it, data ..#7FFF
# above). The default 0x6200 is a 50/50 split; a code-heavy/data-light app (NOTEPAD)
# can pass a higher value to trade its spare data room for code room. Per-app so a
# data-heavy app (VIEWER) keeps the low split. (#97)
DATA_LOC="${DATA_LOC:-0x6200}"

SDCC="${SDCC:-sdcc}"
BIN="$(dirname "$(command -v "$SDCC")")"   # sdasz80 / makebin sit beside sdcc
SDAS="$BIN/sdasz80"
MAKEBIN="$BIN/makebin"

# Keep target-specific object files apart. CPC, MSX and PCW builds may run close
# together (or concurrently outside the top-level Makefile); sharing main.rel
# allowed one target to link another target's conditional drawing code. That is
# fatal on MSX for CPC apps that write directly to #C000.
case " ${APPDEFS:-} " in
    *" -DGB_MSX2 "*) work="build/msx-obj/$(basename "$APP")" ;;
    *" -DGB_PCW "*)  work="build/pcw-obj/$(basename "$APP")" ;;
    *)                work="build/$(basename "$APP")" ;;
esac
mkdir -p "$work"
mkdir -p "$(dirname "$OUT")"
. tools/build_cache.sh

DIALOGS_FLAG="${DIALOGS:-0}"
PROMPT_FLAG="${PROMPT:-0}"
PICKER_FLAG="${PICKER:-0}"
DOC_FLAG="${DOC:-0}"
DOCRO_FLAG="${DOCRO:-0}"
NET_FLAG="${NET:-0}"
GBWIN_FLAG="${GBWIN:-1}"
WIDGETS_FLAG="${WIDGETS:-0}"
BUTTON_FLAG="${BUTTON:-0}"
SCROLL_FLAG="${SCROLL:-0}"
SCROLL16_FLAG="${SCROLL16:-0}"
TOGGLE_FLAG="${TOGGLE:-0}"
STEPPER_FLAG="${STEPPER:-0}"
SELECTOR_FLAG="${SELECTOR:-0}"
SLIDER_FLAG="${SLIDER:-0}"
FORM_FLAG="${FORM:-0}"
FORM_SELECT_FLAG="${FORM_SELECT:-0}"
TIMESET_FLAG="${TIMESET:-0}"
NET_SRC="$GB/gbnet_stub.c"
case " ${APPDEFS:-} " in
    *" -DGB_MSX2 "*) NET_SRC="$GB/gbnet_unapi_stub.c" ;;
esac

if [ "$FORM_FLAG" = "1" ] && [ "$WIDGETS_FLAG" != "1" ]; then
    echo "ERROR: FORM=1 requires WIDGETS=1" >&2
    exit 1
fi
if [ "$FORM_SELECT_FLAG" = "1" ] &&
   { [ "$FORM_FLAG" != "1" ] || [ "$SELECTOR_FLAG" != "1" ]; }; then
    echo "ERROR: FORM_SELECT=1 requires FORM=1 and SELECTOR=1" >&2
    exit 1
fi

deps=("$0" "tools/build_cache.sh" "$GB/crt0.s" "$GBLIB_SRC" "$GB/gb.h")
if [ "$GBWIN_FLAG" = "1" ]; then
    deps+=("$GB/gbwin.c")
fi
if [ "$WIDGETS_FLAG" = "1" ] || [ "$BUTTON_FLAG" = "1" ]; then
    deps+=("$GB/gbwidgets.c")
fi
if [ "$SCROLL_FLAG" = "1" ]; then
    deps+=("$GB/gbscroll.c")
fi
if [ "$SCROLL16_FLAG" = "1" ]; then
    deps+=("$GB/gbscroll16.c")
fi
if [ "$TOGGLE_FLAG" = "1" ]; then
    deps+=("$GB/gbtoggle.c")
fi
if [ "$STEPPER_FLAG" = "1" ]; then
    deps+=("$GB/gbstepper.c")
fi
if [ "$SELECTOR_FLAG" = "1" ]; then
    deps+=("$GB/gbselect.c")
fi
if [ "$SLIDER_FLAG" = "1" ]; then
    deps+=("$GB/gbslider.c")
fi
if [ "$FORM_FLAG" = "1" ]; then
    deps+=("$GB/gbform.c")
fi
if [ "$FORM_SELECT_FLAG" = "1" ]; then
    deps+=("$GB/gbform_select.c")
fi
if [ "$TIMESET_FLAG" = "1" ]; then
    deps+=("$GB/gbsettime.c")
fi
while IFS= read -r dep; do
    deps+=("$dep")
done < <(find "$APP" -type f | sort)
if grep -Rqs 'gbhttp\.h' "$APP"; then
    deps+=("$GB/gbhttp.h")
fi
if grep -Rqs 'gbhtml\.h' "$APP"; then
    deps+=("$GB/gbhtml.h")
fi
if [ "$DIALOGS_FLAG" = "1" ] || [ "$PROMPT_FLAG" = "1" ] || [ "$PICKER_FLAG" = "1" ] || [ "$DOC_FLAG" = "1" ] || [ "$DOCRO_FLAG" = "1" ]; then
    deps+=("$GB/gbui_stub.c")
fi
if [ "$DOC_FLAG" = "1" ] || [ "$DOCRO_FLAG" = "1" ]; then
    deps+=("$GB/gbdoc.c")
fi
if [ "$NET_FLAG" = "1" ]; then
    deps+=("$NET_SRC")
fi

stamp="$OUT.stamp"
cache_key=$(printf '%s\n' \
    "build_capp.v1" \
    "APP=$APP" \
    "DATA_LOC=$DATA_LOC" \
    "APPDEFS=${APPDEFS:-}" \
    "DIALOGS=$DIALOGS_FLAG" \
    "PROMPT=$PROMPT_FLAG" \
    "PICKER=$PICKER_FLAG" \
    "DOC=$DOC_FLAG" \
    "DOCRO=$DOCRO_FLAG" \
    "NET=$NET_FLAG" \
    "NET_SRC=$NET_SRC" \
    "GBWIN=$GBWIN_FLAG" \
    "WIDGETS=$WIDGETS_FLAG" \
    "BUTTON=$BUTTON_FLAG" \
    "SCROLL=$SCROLL_FLAG" \
    "SCROLL16=$SCROLL16_FLAG" \
    "TOGGLE=$TOGGLE_FLAG" \
    "STEPPER=$STEPPER_FLAG" \
    "SELECTOR=$SELECTOR_FLAG" \
    "SLIDER=$SLIDER_FLAG" \
    "FORM=$FORM_FLAG" \
    "FORM_SELECT=$FORM_SELECT_FLAG" \
    "TIMESET=$TIMESET_FLAG" \
    "GBLIB_SRC=$GBLIB_SRC" \
    "APP_CFLAGS=$APP_CFLAGS" \
    "LOAD_LIMIT=$LOAD_LIMIT" \
    "SDCC=$SDCC" \
    "SDAS=$SDAS" \
    "MAKEBIN=$MAKEBIN")
if ! gb_needs_rebuild "$OUT" "$stamp" "$cache_key" "${deps[@]}"; then
    echo "Up to date $OUT ($(stat -c%s "$OUT") bytes) from $APP"
    exit 0
fi

"$SDAS" -o "$work/crt0.rel"  "$GB/crt0.s"
"$SDAS" -o "$work/gblib.rel" "$GBLIB_SRC"
# --fomit-frame-pointer: frame on IY, not IX. The kernel/fs code uses IX as a
# scratch (it never touches IY) and firmware calls preserve the caller's IY, so
# this stops a kernel call from wrecking an app's frame pointer (which crashed
# the notepad's return - SDCC's epilogue is `ld sp,<fp>`).
# APPDEFS (e.g. -DGB_MSX2) MUST reach every libgb C unit, not just main.c: gb.h
# derives GB_COLS/GB_LINES/GB_XPIX from it, and gbwin.c/gbdoc.c clamp window
# drag/resize + fullscreen to those extents. Omitting it built libgb with the
# CPC 320x200 extents, so on MSX windows would not drag past x=320 (#287).
"$SDCC" -mz80 --fomit-frame-pointer $APP_CFLAGS ${APPDEFS:-} -I "$GB" -c "$APP/main.c" -o "$work/main.rel"
GBWIN_REL=""
if [ "$GBWIN_FLAG" = "1" ]; then
    "$SDCC" -mz80 --fomit-frame-pointer ${APPDEFS:-} -I "$GB" -c "$GB/gbwin.c" -o "$work/gbwin.rel"
    GBWIN_REL="$work/gbwin.rel"
fi
WIDGETS_REL=""
if [ "$WIDGETS_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer ${APPDEFS:-} -I "$GB" -c "$GB/gbwidgets.c" -o "$work/gbwidgets.rel"
    WIDGETS_REL="$work/gbwidgets.rel"
elif [ "$BUTTON_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer -DGB_BUTTON_ONLY ${APPDEFS:-} -I "$GB" -c "$GB/gbwidgets.c" -o "$work/gbwidgets.rel"
    WIDGETS_REL="$work/gbwidgets.rel"
fi
SCROLL_REL=""
if [ "$SCROLL_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer ${APPDEFS:-} -I "$GB" -c "$GB/gbscroll.c" -o "$work/gbscroll.rel"
    SCROLL_REL="$work/gbscroll.rel"
fi
SCROLL16_REL=""
if [ "$SCROLL16_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer ${APPDEFS:-} -I "$GB" -c "$GB/gbscroll16.c" -o "$work/gbscroll16.rel"
    SCROLL16_REL="$work/gbscroll16.rel"
fi
TOGGLE_REL=""
if [ "$TOGGLE_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer ${APPDEFS:-} -I "$GB" -c "$GB/gbtoggle.c" -o "$work/gbtoggle.rel"
    TOGGLE_REL="$work/gbtoggle.rel"
fi
STEPPER_REL=""
if [ "$STEPPER_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer ${APPDEFS:-} -I "$GB" -c "$GB/gbstepper.c" -o "$work/gbstepper.rel"
    STEPPER_REL="$work/gbstepper.rel"
fi
SELECTOR_REL=""
if [ "$SELECTOR_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer ${APPDEFS:-} -I "$GB" -c "$GB/gbselect.c" -o "$work/gbselect.rel"
    SELECTOR_REL="$work/gbselect.rel"
fi
SLIDER_REL=""
if [ "$SLIDER_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer ${APPDEFS:-} -I "$GB" -c "$GB/gbslider.c" -o "$work/gbslider.rel"
    SLIDER_REL="$work/gbslider.rel"
fi
FORM_REL=""
if [ "$FORM_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer ${APPDEFS:-} -I "$GB" -c "$GB/gbform.c" -o "$work/gbform.rel"
    FORM_REL="$work/gbform.rel"
fi
FORM_SELECT_REL=""
if [ "$FORM_SELECT_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer ${APPDEFS:-} -I "$GB" -c "$GB/gbform_select.c" -o "$work/gbform_select.rel"
    FORM_SELECT_REL="$work/gbform_select.rel"
fi
TIMESET_REL=""
if [ "$TIMESET_FLAG" = "1" ]; then
    "$SDCC" -mz80 --opt-code-size --fomit-frame-pointer ${APPDEFS:-} -I "$GB" -c "$GB/gbsettime.c" -o "$work/gbsettime.rel"
    TIMESET_REL="$work/gbsettime.rel"
fi
# Opt-in dialogs (#114, #142). The heavy render (popup/prompt/file-picker) now lives in
# the paged GBUI kernel module (#142 step 1b); an app that needs ANY dialog links only
# the tiny marshalling stub gbui_stub.c (gb_popup/gb_prompt/gb_pickfile/gb_pickdir ->
# GB_UI). That ~800-byte/app saving is what lets the data-heavy apps fit gb_doc.
#   DIALOGS / PROMPT / PICKER  -> gbui_stub.c (the stubs)
#   DOC=1                      -> gbdoc.c too (the document/File-menu framework)
DLG_REL=""
if [ "$DIALOGS_FLAG" = "1" ] || [ "$PROMPT_FLAG" = "1" ] || [ "$PICKER_FLAG" = "1" ] || [ "$DOC_FLAG" = "1" ] || [ "$DOCRO_FLAG" = "1" ]; then
    "$SDCC" -mz80 --fomit-frame-pointer ${APPDEFS:-} -I "$GB" -c "$GB/gbui_stub.c" -o "$work/gbui_stub.rel"
    DLG_REL="$work/gbui_stub.rel"
fi
# DOC=1 = the full document framework; DOCRO=1 = a READ-ONLY variant (-DGBDOC_RO) that
# omits the Save/Save As path, so a viewer-style app saves that code room (#144).
if [ "$DOC_FLAG" = "1" ] || [ "$DOCRO_FLAG" = "1" ]; then
    RO=""; [ "$DOCRO_FLAG" = "1" ] && RO="-DGBDOC_RO"
    "$SDCC" -mz80 --fomit-frame-pointer $RO ${APPDEFS:-} -I "$GB" -c "$GB/gbdoc.c" -o "$work/gbdoc.rel"
    DLG_REL="$DLG_REL $work/gbdoc.rel"
fi
# NET=1 uses the target's gb_net_* backend. CPC calls the active paged GBNET
# module; MSX apps call a discovered TCP/IP UNAPI implementation directly.
if [ "$NET_FLAG" = "1" ]; then
    "$SDCC" -mz80 --fomit-frame-pointer ${APPDEFS:-} -I "$GB" -c "$NET_SRC" -o "$work/gbnet_stub.rel"
    DLG_REL="$DLG_REL $work/gbnet_stub.rel"
fi
"$SDCC" -mz80 --no-std-crt0 --code-loc 0x4000 --data-loc "$DATA_LOC" \
    "$work/crt0.rel" "$work/main.rel" $GBWIN_REL $WIDGETS_REL $SCROLL_REL $SCROLL16_REL \
    $TOGGLE_REL $STEPPER_REL $SELECTOR_REL $SLIDER_REL $FORM_REL \
    $FORM_SELECT_REL $TIMESET_REL $DLG_REL \
    "$work/gblib.rel" -o "$work/app.ihx"
# STABILITY GUARD: the app must fit its 16K page. The whole LOADED IMAGE
# (_CODE + the startup tails _GSINIT/_GSFINAL/_INITIALIZER, which the linker places
# AFTER the code) must end below data-loc - otherwise the RAM data area starts inside
# it and gsinit zeroes its own code as it runs -> instant reboot (bit NOTEPAD: a
# _CODE-only check passed while _GSINIT overlapped _DATA). And data+bss must end below
# the kernel (#8000). LOAD_LIMIT mirrors the target's app loader ceiling; it is
# #7F00 by default and #7F80 only for PCW Browser's record-rounded image.
python3 - "$work/app.map" "$APP" "$DATA_LOC" "$LOAD_LIMIT" <<'PY'
import sys, re
mapf, app = sys.argv[1], sys.argv[2]
dloc, load_limit = int(sys.argv[3], 16), int(sys.argv[4], 16)
area = {}
for line in open(mapf):
    m = re.match(r'^(_CODE|_HOME|_DATA|_BSS|_INITIALIZED|_GSINIT|_GSFINAL|_INITIALIZER)\s+([0-9A-Fa-f]{8})\s+([0-9A-Fa-f]{8})', line)
    if m:
        area[m.group(1)] = (int(m.group(2), 16), int(m.group(3), 16))
LOAD = ('_CODE', '_GSINIT', '_GSFINAL', '_HOME', '_INITIALIZER') # loaded image (before data-loc)
img_end = max((area[a][0] + area[a][1]) for a in LOAD if a in area)
top = max((s + sz) for s, sz in area.values()) if area else 0
errs = []
if img_end > dloc:  errs.append('loaded image ends 0x%04X > data-loc 0x%04X (gsinit/data overlap)' % (img_end, dloc))
if img_end > load_limit: errs.append('loaded image ends 0x%04X > app loader limit 0x%04X' % (img_end, load_limit))
if top > 0x8000:    errs.append('data/bss ends 0x%04X > kernel 0x8000' % top)
if errs:
    sys.stderr.write('FIT ERROR (%s): %s - shrink it or raise DATA_LOC\n' % (app, '; '.join(errs)))
    sys.exit(1)
PY

"$MAKEBIN" -p "$work/app.ihx" "$work/app.bin"

# makebin emits a flat image from #0000; the app lives at #4000 -> strip low 16K.
tail -c +16385 "$work/app.bin" > "$OUT"
gb_write_stamp "$stamp" "$cache_key"
echo "Built $OUT ($(stat -c%s "$OUT") bytes) from $APP"
