#!/usr/bin/env bash
# Assemble the AMSDOS/floppy WRITE module (kernel/modules/floppysv.asm) into a raw
# DATA_MODTOP image: build/FLOPPYSV.RAW. The kernel pages it into the free upper
# part of PAGE_DATA and CALLs it on a floppy save (issue #135). The module's own
# `save` directive writes the RAW; this script just runs RASM.
#   tools/build_floppymod.sh
set -euo pipefail
cd "$(dirname "$0")/.."
RASM="${RASM:-rasm}"
mkdir -p build
. tools/build_cache.sh

OUT="build/FLOPPYSV.RAW"
deps=("$0" "tools/build_cache.sh" "kernel/modules/floppysv.asm" "lib/fs_amsdos_core.asm")
stamp="$OUT.stamp"
cache_key=$(printf '%s\n' "build_floppymod.v1" "RASM=$RASM" "EXTRA_RASM=${EXTRA_RASM:-}")
if ! gb_needs_rebuild "$OUT" "$stamp" "$cache_key" "${deps[@]}"; then
    echo "Up to date $OUT ($(stat -c%s "$OUT") bytes)"
    exit 0
fi

"$RASM" kernel/modules/floppysv.asm -eo ${EXTRA_RASM:-}
gb_write_stamp "$stamp" "$cache_key"
echo "Built $OUT ($(stat -c%s "$OUT") bytes)"
