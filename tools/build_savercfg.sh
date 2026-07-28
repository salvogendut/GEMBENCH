#!/usr/bin/env bash
# Build a same-stem screensaver configuration companion at #6000.
#
# The kernel pages these modules through the existing arbitrary GB_UI path.
# They draw their own modal controls and return key/value updates through
# lib/gb/gbsavercfg.h; SETTINGS.APP remains saver-agnostic.
#
#   tools/build_savercfg.sh apps/xmatrix build/XMATRIXCFG.RAW
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: tools/build_savercfg.sh apps/<saver> <out.RAW>}"
OUT="${2:?usage: tools/build_savercfg.sh apps/<saver> <out.RAW>}"
GB="lib/gb"
SRC="$APP/config.c"
DATA_LOC="0x7800"

[ -f "$SRC" ] || { echo "ERROR: missing screensaver config source $SRC" >&2; exit 1; }

SDCC="${SDCC:-sdcc}"
BIN="$(dirname "$(command -v "$SDCC")")"
SDAS="$BIN/sdasz80"
MAKEBIN="$BIN/makebin"

case " ${APPDEFS:-} " in
    *" -DGB_MSX2 "*) work="build/msx-obj/savercfg-$(basename "$APP")" ;;
    *" -DGB_PCW "*)  work="build/pcw-obj/savercfg-$(basename "$APP")" ;;
    *)                work="build/savercfg-$(basename "$APP")" ;;
esac
mkdir -p "$work"
mkdir -p "$(dirname "$OUT")"
. tools/build_cache.sh

deps=("$0" "tools/build_cache.sh" "$GB/crt0.s" "$GB/gblib.s" "$GB/gb.h"
      "$GB/gbcfg.h" "$GB/gbsaver.h" "$GB/gbsavercfg.h"
      "$GB/gbactions.c" "$GB/gbstepper.c" "$SRC")
stamp="$OUT.stamp"
cache_key=$(printf '%s\n' \
    "build_savercfg.v1" \
    "APP=$APP" \
    "APPDEFS=${APPDEFS:-}" \
    "DATA_LOC=$DATA_LOC" \
    "SDCC=$SDCC" \
    "SDAS=$SDAS" \
    "MAKEBIN=$MAKEBIN")
if ! gb_needs_rebuild "$OUT" "$stamp" "$cache_key" "${deps[@]}"; then
    echo "Up to date $OUT ($(stat -c%s "$OUT") bytes) from $SRC"
    exit 0
fi

"$SDAS" -o "$work/crt0.rel" "$GB/crt0.s"
"$SDAS" -o "$work/gblib.rel" "$GB/gblib.s"
"$SDCC" -mz80 --opt-code-size --max-allocs-per-node 100000 \
    --fomit-frame-pointer ${APPDEFS:-} -I "$GB" \
    -c "$SRC" -o "$work/config.rel"
"$SDCC" -mz80 --opt-code-size --fomit-frame-pointer ${APPDEFS:-} -I "$GB" \
    -c "$GB/gbactions.c" -o "$work/gbactions.rel"
"$SDCC" -mz80 --opt-code-size --fomit-frame-pointer ${APPDEFS:-} -I "$GB" \
    -c "$GB/gbstepper.c" -o "$work/gbstepper.rel"
"$SDCC" -mz80 --no-std-crt0 --code-loc 0x6000 --data-loc "$DATA_LOC" \
    "$work/crt0.rel" "$work/config.rel" "$work/gbactions.rel" \
    "$work/gbstepper.rel" "$work/gblib.rel" -o "$work/mod.ihx"

python3 - "$work/mod.map" "$APP" "$DATA_LOC" <<'PY'
import re
import sys

map_file, app, data_loc_text = sys.argv[1:]
data_loc = int(data_loc_text, 16)
areas = {}
for line in open(map_file):
    match = re.match(
        r'^(_CODE|_HOME|_DATA|_BSS|_INITIALIZED|_GSINIT|_GSFINAL|_INITIALIZER)'
        r'\s+([0-9A-Fa-f]{8})\s+([0-9A-Fa-f]{8})',
        line,
    )
    if match:
        areas[match.group(1)] = (int(match.group(2), 16), int(match.group(3), 16))

loaded = ('_CODE', '_GSINIT', '_GSFINAL', '_HOME', '_INITIALIZER')
image_end = max(areas[name][0] + areas[name][1] for name in loaded if name in areas)
top = max(start + size for start, size in areas.values()) if areas else 0
errors = []
if image_end > data_loc:
    errors.append(f'loaded image ends 0x{image_end:04X} > data-loc 0x{data_loc:04X}')
if top > 0x8000:
    errors.append(f'data/bss ends 0x{top:04X} > 0x8000')
if errors:
    sys.stderr.write(f'FIT ERROR ({app} config): ' + '; '.join(errors) + '\n')
    sys.exit(1)
PY

"$MAKEBIN" -p "$work/mod.ihx" "$work/mod.bin"
tail -c +24577 "$work/mod.bin" > "$OUT"
gb_write_stamp "$stamp" "$cache_key"
echo "Built $OUT ($(stat -c%s "$OUT") bytes) from $SRC"
