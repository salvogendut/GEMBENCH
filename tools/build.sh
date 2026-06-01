#!/usr/bin/env bash
# Assemble GEOBENCH into a bootable .dsk image.
#
# Output: build/geobench.dsk  (contains GEOBENCH.BIN, AMSDOS-headed)
# Run with:  ../1984/1984 --disk-a=build/geobench.dsk --autostart=GEOBENCH
#
# Uses $RASM if set, else 'rasm' from PATH.
set -euo pipefail

cd "$(dirname "$0")/.."          # repo root
RASM="${RASM:-rasm}"

mkdir -p build
"$RASM" desktop/main.asm -eo          # -eo: overwrite the .dsk if it exists
echo "Built build/geobench.dsk"
