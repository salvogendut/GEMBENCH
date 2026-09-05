#!/usr/bin/env bash
# Build the MSX2 GBFSCTX.MOD implementation at DATA_MODTOP (#6000).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/msx/GBFSCTX.RAW}"
GB="lib/gb"
KC="kernel/kc"
SDCC="${SDCC:-sdcc}"
BIN="$(dirname "$(command -v "$SDCC")")"
SDAS="$BIN/sdasz80"
MAKEBIN="$BIN/makebin"
work="build/fsctxmod"
mkdir -p "$work" "$(dirname "$OUT")"
. tools/build_cache.sh

deps=("$0" tools/build_cache.sh tools/gblib_subset.py "$GB/crt0.s" "$GB/gblib.s" \
      "$GB/gb.h" "$KC/gbfsctx_mod.c" "$KC/gbfsctx_msx.s" "$KC/gbfsctx.symbols"
      "$KC/msx_fsctx.h" kernel/core/fsctx_layout.h kernel/core/fsctx_contract.h
      kernel/core/fsctx_policy.inc)
stamp="$OUT.stamp"
cache_key=$(printf '%s\n' "build_fsctxmod.v1" "SDCC=$SDCC" "SDAS=$SDAS" "MAKEBIN=$MAKEBIN")
if ! gb_needs_rebuild "$OUT" "$stamp" "$cache_key" "${deps[@]}"; then
    echo "Up to date $OUT ($(stat -c%s "$OUT") bytes)"
    exit 0
fi

python3 tools/gblib_subset.py "$GB/gblib.s" "$work/gblib.s" "$KC/gbfsctx.symbols"
"$SDAS" -o "$work/crt0.rel" "$GB/crt0.s"
"$SDAS" -o "$work/gblib.rel" "$work/gblib.s"
"$SDAS" -o "$work/msx.rel" "$KC/gbfsctx_msx.s"
"$SDCC" -mz80 --opt-code-size --max-allocs-per-node 100000 --fomit-frame-pointer \
    -DGB_MSX2 -I "$GB" -c "$KC/gbfsctx_mod.c" -o "$work/mod.rel"
"$SDCC" -mz80 --no-std-crt0 --code-loc 0x6000 --data-loc 0x7F00 \
    "$work/crt0.rel" "$work/mod.rel" "$work/msx.rel" "$work/gblib.rel" \
    -o "$work/mod.ihx"

python3 tools/check_app_layout.py "$work/mod.map" --app GBFSCTX.MOD \
    --data-loc 0x7F00 --load-limit 0x7F00 --task-stack-reserve 0
"$MAKEBIN" -p "$work/mod.ihx" "$work/mod.bin"
tail -c +24577 "$work/mod.bin" > "$OUT"
gb_write_stamp "$stamp" "$cache_key"
echo "Built $OUT ($(stat -c%s "$OUT") bytes)"
