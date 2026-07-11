#!/usr/bin/env bash
# Build GBWEB.MOD, the Browser's paged source-cache/config helper.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/GBWEB.RAW}"
GB="lib/gb"
SRC="kernel/kc/gbweb_mod.c"
SDCC="${SDCC:-sdcc}"
BIN="$(dirname "$(command -v "$SDCC")")"
SDAS="$BIN/sdasz80"
MAKEBIN="$BIN/makebin"
work="build/webmod"
mkdir -p "$work" "$(dirname "$OUT")"
. tools/build_cache.sh

deps=("$0" "tools/build_cache.sh" "$GB/crt0.s" "$GB/gblib.s" "$GB/gb.h" \
      "$GB/gbform.h" "$GB/gburl.h" "$SRC")
stamp="$OUT.stamp"
cache_key=$(printf '%s\n' "build_webmod.v1" "SDCC=$SDCC" "SDAS=$SDAS" "MAKEBIN=$MAKEBIN")
if ! gb_needs_rebuild "$OUT" "$stamp" "$cache_key" "${deps[@]}"; then
    echo "Up to date $OUT ($(stat -c%s "$OUT") bytes)"
    exit 0
fi

"$SDAS" -o "$work/crt0.rel" "$GB/crt0.s"
"$SDAS" -o "$work/gblib.rel" "$GB/gblib.s"
"$SDCC" -mz80 --fomit-frame-pointer -I "$GB" -c "$SRC" -o "$work/gbweb_mod.rel"
"$SDCC" -mz80 --no-std-crt0 --code-loc 0x6000 --data-loc 0x7800 \
    "$work/crt0.rel" "$work/gbweb_mod.rel" "$work/gblib.rel" -o "$work/mod.ihx"

python3 - "$work/mod.map" <<'PY'
import re, sys
area = {}
for line in open(sys.argv[1]):
    m = re.match(r'^(_CODE|_DATA|_BSS|_INITIALIZED|_GSINIT|_GSFINAL|_INITIALIZER)\s+([0-9A-Fa-f]{8})\s+([0-9A-Fa-f]{8})', line)
    if m:
        area[m.group(1)] = (int(m.group(2), 16), int(m.group(3), 16))
load = ('_CODE', '_GSINIT', '_GSFINAL', '_INITIALIZER')
image_end = max(area[a][0] + area[a][1] for a in load if a in area)
top = max(start + size for start, size in area.values())
if image_end > 0x7800 or top > 0x8000:
    raise SystemExit('FIT ERROR (GBWEB): image=0x%04X top=0x%04X' % (image_end, top))
PY

"$MAKEBIN" -p "$work/mod.ihx" "$work/mod.bin"
tail -c +24577 "$work/mod.bin" > "$OUT"
gb_write_stamp "$stamp" "$cache_key"
echo "Built $OUT ($(stat -c%s "$OUT") bytes)"
