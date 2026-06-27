#!/usr/bin/env bash
# Build GBNET.MOD (#238): the W5100S socket driver (cpc-sdcc w5100.c/net.c +
# gbnet_init.c) behind a one-entry op-selector dispatcher (gbnet_mod.c), as a paged
# binary the kernel loads at DATA_MODTOP (#6000 in PAGE_DATA) on a GB_NET call. Pure
# port I/O - it links no gblib (unlike GBUI).
#
#   tools/build_netmod.sh [out.RAW]      (default build/GBNET.RAW)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/GBNET.RAW}"
KC="kernel/kc"
GB="lib/gb"

SDCC="${SDCC:-sdcc}"
BIN="$(dirname "$(command -v "$SDCC")")"
SDAS="$BIN/sdasz80"
MAKEBIN="$BIN/makebin"

work="build/netmod"
mkdir -p "$work"

"$SDAS" -o "$work/crt0.rel" "$GB/crt0.s"
"$SDCC" -mz80 --fomit-frame-pointer -I "$KC" -c "$KC/gbnet_mod.c"  -o "$work/gbnet_mod.rel"
"$SDCC" -mz80 --fomit-frame-pointer -I "$KC" -c "$KC/w5100.c"      -o "$work/w5100.rel"
"$SDCC" -mz80 --fomit-frame-pointer -I "$KC" -c "$KC/net.c"        -o "$work/net.rel"
"$SDCC" -mz80 --fomit-frame-pointer -I "$KC" -c "$KC/gbnet_init.c" -o "$work/gbnet_init.rel"
"$SDCC" -mz80 --fomit-frame-pointer -I "$KC" -c "$KC/udp.c"        -o "$work/udp.rel"
"$SDCC" -mz80 --fomit-frame-pointer -I "$KC" -c "$KC/dns.c"        -o "$work/dns.rel"
# code at #6000 (the module load address); data above it, all below the kernel (#8000).
"$SDCC" -mz80 --no-std-crt0 --code-loc 0x6000 --data-loc 0x7400 \
    "$work/crt0.rel" "$work/gbnet_mod.rel" "$work/w5100.rel" "$work/net.rel" \
    "$work/gbnet_init.rel" "$work/udp.rel" "$work/dns.rel" -o "$work/mod.ihx"

# fit guard: loaded image (code + gsinit tail) clears data-loc, data/bss ends below #8000.
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
if img > 0x7400: e.append('image ends 0x%04X > data-loc 0x7400'%img)
if top > 0x8000: e.append('data/bss ends 0x%04X > 0x8000'%top)
if e: sys.stderr.write('FIT ERROR (GBNET): '+'; '.join(e)+'\n'); sys.exit(1)
PY

"$MAKEBIN" -p "$work/mod.ihx" "$work/mod.bin"
# makebin emits a flat image from #0000; the module lives at #6000 -> strip the low 24K.
tail -c +24577 "$work/mod.bin" > "$OUT"
echo "Built $OUT ($(stat -c%s "$OUT") bytes)"
