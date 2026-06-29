#!/usr/bin/env bash
# Build the GBCFG kernel module: the config parser as a loadable #4000 image the
# kernel pages into a bank and CALLs at boot (issue #30). Same image format as
# the C apps (crt0 first -> _start at #4000), but linked without libgb - the
# module reaches nothing in the kernel, it only reads/writes the low-RAM transfer
# area (see kernel/kc/kcfg_mod.c).
#
#   tools/build_cfgmod.sh [out.RAW]      (default build/GBCFG.RAW)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/GBCFG.RAW}"
GB="lib/gb"
KC="kernel/kc"

SDCC="${SDCC:-sdcc}"
BIN="$(dirname "$(command -v "$SDCC")")"
SDAS="$BIN/sdasz80"
MAKEBIN="$BIN/makebin"

work="build/cfgmod"
mkdir -p "$work"
mkdir -p "$(dirname "$OUT")"
. tools/build_cache.sh

deps=("$0" "tools/build_cache.sh" "$GB/crt0.s" "$KC/kcfg_mod.c" "$KC/kcfg.c" "$KC/kcfg.h")
stamp="$OUT.stamp"
cache_key=$(printf '%s\n' \
    "build_cfgmod.v1" \
    "SDCC=$SDCC" \
    "SDAS=$SDAS" \
    "MAKEBIN=$MAKEBIN")
if ! gb_needs_rebuild "$OUT" "$stamp" "$cache_key" "${deps[@]}"; then
    echo "Up to date $OUT ($(stat -c%s "$OUT") bytes)"
    exit 0
fi

"$SDAS" -o "$work/crt0.rel" "$GB/crt0.s"
# --fomit-frame-pointer to match the app/kernel IX convention (the parser does
# not care, but keep the toolchain flags uniform across all GEOBENCH C).
"$SDCC" -mz80 --fomit-frame-pointer -I "$KC" -c "$KC/kcfg_mod.c" -o "$work/kcfg_mod.rel"
"$SDCC" -mz80 --fomit-frame-pointer -I "$KC" -c "$KC/kcfg.c"     -o "$work/kcfg.rel"
"$SDCC" -mz80 --no-std-crt0 --code-loc 0x4000 --data-loc 0x6000 \
    "$work/crt0.rel" "$work/kcfg_mod.rel" "$work/kcfg.rel" -o "$work/mod.ihx"
"$MAKEBIN" -p "$work/mod.ihx" "$work/mod.bin"

# makebin emits from #0000; the module lives at #4000 -> strip the low 16K.
tail -c +16385 "$work/mod.bin" > "$OUT"
gb_write_stamp "$stamp" "$cache_key"
echo "Built $OUT ($(stat -c%s "$OUT") bytes)"
