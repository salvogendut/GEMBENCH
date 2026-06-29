#!/usr/bin/env bash
# Assemble the FAT16/IDE write module (kernel/modules/gbfat.asm) into a raw
# #5000 image: build/GBFAT.RAW. The kernel pages it into the free upper part of
# PAGE_DATA and CALLs it on an IDE save (issue #34). The module's own `save`
# directive writes the RAW; this script just runs RASM.
#   tools/build_fatmod.sh
set -euo pipefail
cd "$(dirname "$0")/.."
RASM="${RASM:-rasm}"
mkdir -p build
. tools/build_cache.sh

OUT="build/GBFAT.RAW"
deps=("$0" "tools/build_cache.sh" "kernel/modules/gbfat.asm" "lib/fs_fat32_core.asm")
stamp="$OUT.stamp"
cache_key=$(printf '%s\n' "build_fatmod.v1" "RASM=$RASM")
if ! gb_needs_rebuild "$OUT" "$stamp" "$cache_key" "${deps[@]}"; then
    echo "Up to date $OUT ($(stat -c%s "$OUT") bytes)"
    exit 0
fi

"$RASM" kernel/modules/gbfat.asm -eo
gb_write_stamp "$stamp" "$cache_key"
echo "Built $OUT ($(stat -c%s "$OUT") bytes)"
