#!/usr/bin/env bash
# Assemble the M4 board WRITE module (kernel/modules/m4save.asm) into a raw
# DATA_MODTOP image: build/M4SAVE.RAW. The resident M4 backend stages save
# requests into low RAM and loads this module on demand.
set -euo pipefail
cd "$(dirname "$0")/.."
RASM="${RASM:-rasm}"
mkdir -p build
. tools/build_cache.sh

OUT="build/M4SAVE.RAW"
deps=("$0" "tools/build_cache.sh" "kernel/modules/m4save.asm")
stamp="$OUT.stamp"
cache_key=$(printf '%s\n' "build_m4savemod.v1" "RASM=$RASM")
if ! gb_needs_rebuild "$OUT" "$stamp" "$cache_key" "${deps[@]}"; then
    echo "Up to date $OUT ($(stat -c%s "$OUT") bytes)"
    exit 0
fi

"$RASM" kernel/modules/m4save.asm -eo
gb_write_stamp "$stamp" "$cache_key"
echo "Built $OUT ($(stat -c%s "$OUT") bytes)"
