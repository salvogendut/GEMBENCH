#!/usr/bin/env bash
# Build the GBUI dialog module (#142, step 1b): the shared dialog render code
# (gbdlg + gbprompt + gbpick) plus a tiny dispatcher, as a paged binary the kernel
# loads at DATA_MODTOP (#6000 in PAGE_DATA) on a GB_UI call. Unlike an app it links
# gblib (it calls resident gb_poll/fill/text/dir1) and lives at #6000, not #4000.
#
#   tools/build_uimod.sh [out.RAW]      (default build/GBUI.RAW)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/GBUI.RAW}"
GB="lib/gb"
KC="kernel/kc"

SDCC="${SDCC:-sdcc}"
BIN="$(dirname "$(command -v "$SDCC")")"
SDAS="$BIN/sdasz80"
MAKEBIN="$BIN/makebin"

work="build/uimod"
mkdir -p "$work"
mkdir -p "$(dirname "$OUT")"
. tools/build_cache.sh

BUILD_VERSION="${VERSION:-$(tr -d '\r\n' < VERSION)}"
BUILD_COMMIT="${GIT_COMMIT:-$(git rev-parse --short=12 HEAD 2>/dev/null || printf unknown)}"
case "$BUILD_VERSION" in
    ""|*[!A-Za-z0-9._+-]*) echo "ERROR: invalid VERSION: $BUILD_VERSION" >&2; exit 2 ;;
esac
[ "${#BUILD_VERSION}" -le 12 ] || { echo "ERROR: VERSION is longer than 12 characters" >&2; exit 2; }
case "$BUILD_COMMIT" in
    ""|*[!A-Za-z0-9._+-]*) echo "ERROR: invalid GIT_COMMIT: $BUILD_COMMIT" >&2; exit 2 ;;
esac
[ "${#BUILD_COMMIT}" -le 13 ] || { echo "ERROR: GIT_COMMIT is longer than 13 characters" >&2; exit 2; }
BUILD_DEFS=(-DGB_VERSION="\"$BUILD_VERSION\"" -DGB_GIT="\"$BUILD_COMMIT\"")

deps=("$0" "tools/build_cache.sh" "$GB/crt0.s" "$GB/gblib.s" "$GB/gb.h" \
      "$GB/gbdlg.c" "$GB/gbprompt.c" "$GB/gbpick.c" "$KC/gbui_mod.c" "VERSION")
stamp="$OUT.stamp"
cache_key=$(printf '%s\n' \
    "build_uimod.v2" \
    "VERSION=$BUILD_VERSION" \
    "GIT=$BUILD_COMMIT" \
    "SDCC=$SDCC" \
    "SDAS=$SDAS" \
    "MAKEBIN=$MAKEBIN")
if ! gb_needs_rebuild "$OUT" "$stamp" "$cache_key" "${deps[@]}"; then
    echo "Up to date $OUT ($(stat -c%s "$OUT") bytes)"
    exit 0
fi

"$SDAS" -o "$work/crt0.rel"  "$GB/crt0.s"
"$SDAS" -o "$work/gblib.rel" "$GB/gblib.s"
"$SDCC" -mz80 --opt-code-size --max-allocs-per-node 100000 --fomit-frame-pointer \
    "${BUILD_DEFS[@]}" -I "$GB" -c "$KC/gbui_mod.c" -o "$work/gbui_mod.rel"
"$SDCC" -mz80 --opt-code-size --max-allocs-per-node 100000 --fomit-frame-pointer \
    -I "$GB" -c "$GB/gbdlg.c" -o "$work/gbdlg.rel"
"$SDCC" -mz80 --opt-code-size --max-allocs-per-node 100000 --fomit-frame-pointer \
    -I "$GB" -c "$GB/gbprompt.c" -o "$work/gbprompt.rel"
"$SDCC" -mz80 --opt-code-size --max-allocs-per-node 100000 --fomit-frame-pointer \
    -I "$GB" -c "$GB/gbpick.c" -o "$work/gbpick.rel"
# code at #6000 (the module load address); data above it, all below the kernel (#8000).
# Popup save-under pixels use gb_copybuf, so the module retains only compact state.
"$SDCC" -mz80 --no-std-crt0 --code-loc 0x6000 --data-loc 0x7780 \
    "$work/crt0.rel" "$work/gbui_mod.rel" "$work/gbdlg.rel" "$work/gbprompt.rel" \
    "$work/gbpick.rel" "$work/gblib.rel" -o "$work/mod.ihx"

# fit guard: the whole loaded image (code + gsinit tail) must clear data-loc, and
# data/bss must end below #8000.
python3 - "$work/mod.map" <<'PY'
import sys, re
area = {}
for line in open(sys.argv[1]):
    m = re.match(r'^(_CODE|_DATA|_BSS|_INITIALIZED|_GSINIT|_GSFINAL|_INITIALIZER)\s+([0-9A-Fa-f]{8})\s+([0-9A-Fa-f]{8})', line)
    if m: area[m.group(1)] = (int(m.group(2),16), int(m.group(3),16))
LOAD = ('_CODE','_GSINIT','_GSFINAL','_INITIALIZER')
img = max((area[a][0]+area[a][1]) for a in LOAD if a in area)
top = max((s+sz) for s,sz in area.values()) if area else 0
e=[]
if img > 0x7780: e.append('image ends 0x%04X > data-loc 0x7780'%img)
if top > 0x8000: e.append('data/bss ends 0x%04X > 0x8000'%top)
if e: sys.stderr.write('FIT ERROR (GBUI): '+'; '.join(e)+'\n'); sys.exit(1)
PY

"$MAKEBIN" -p "$work/mod.ihx" "$work/mod.bin"
# makebin emits a flat image from #0000; the module lives at #6000 -> strip the low 24K.
tail -c +24577 "$work/mod.bin" > "$OUT"
gb_write_stamp "$stamp" "$cache_key"
echo "Built $OUT ($(stat -c%s "$OUT") bytes)"
