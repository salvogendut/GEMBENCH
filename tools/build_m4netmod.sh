#!/usr/bin/env bash
# Build GBNETM4.MOD (#259): the M4 TCP socket driver behind the same
# GBNET transfer ABI used by TELNET.APP. It is staged beside the W5100
# GBNET.MOD; the M4 kernel selects this module by name.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/GBNETM4.RAW}"
KC="kernel/kc"
GB="lib/gb"

SDCC="${SDCC:-sdcc}"
BIN="$(dirname "$(command -v "$SDCC")")"
SDAS="$BIN/sdasz80"
MAKEBIN="$BIN/makebin"

work="build/m4netmod"
mkdir -p "$work"
mkdir -p "$(dirname "$OUT")"
. tools/build_cache.sh

deps=("$0" "tools/build_cache.sh" "$GB/crt0.s" "$KC/gbnet_m4_mod.c")
stamp="$OUT.stamp"
cache_key=$(printf '%s\n' \
    "build_m4netmod.v1" \
    "SDCC=$SDCC" \
    "SDAS=$SDAS" \
    "MAKEBIN=$MAKEBIN")
if ! gb_needs_rebuild "$OUT" "$stamp" "$cache_key" "${deps[@]}"; then
    echo "Up to date $OUT ($(stat -c%s "$OUT") bytes)"
    exit 0
fi

"$SDAS" -o "$work/crt0.rel" "$GB/crt0.s"
"$SDCC" -mz80 --fomit-frame-pointer -I "$KC" -c "$KC/gbnet_m4_mod.c" -o "$work/gbnet_m4_mod.rel"
"$SDCC" -mz80 --no-std-crt0 --code-loc 0x6000 --data-loc 0x7600 \
    "$work/crt0.rel" "$work/gbnet_m4_mod.rel" -o "$work/mod.ihx"

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
if img > 0x7600: e.append('image ends 0x%04X > data-loc 0x7600'%img)
if top > 0x8000: e.append('data/bss ends 0x%04X > 0x8000'%top)
if e: sys.stderr.write('FIT ERROR (GBNETM4): '+'; '.join(e)+'\n'); sys.exit(1)
PY

"$MAKEBIN" -p "$work/mod.ihx" "$work/mod.bin"
tail -c +24577 "$work/mod.bin" > "$OUT"
gb_write_stamp "$stamp" "$cache_key"
echo "Built $OUT ($(stat -c%s "$OUT") bytes)"
