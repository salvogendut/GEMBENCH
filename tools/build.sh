#!/usr/bin/env bash
# Assemble GEOBENCH into a bootable .dsk image.
#
# Output: build/geobench.dsk  (GEOBENCH.BIN + GEOBENCH.CFG + DEFAULT.IST) and
#         build/GEOBENCH.RAW. Run with:
#   ../1984/1984 --disk-a=build/geobench.dsk --autostart=GEOBENCH
#
# The icon set is packed first because desktop/main.asm incbins build/DEFAULT.IST
# onto the .dsk. Uses $RASM if set, else 'rasm' from PATH.
set -euo pipefail

cd "$(dirname "$0")/.."          # repo root
RASM="${RASM:-rasm}"

mkdir -p build

# Default icon set, packed in the desktop's slot order (keep in sync with
# icon_set in desktop/main.asm).
python3 tools/packicons.py build/DEFAULT.IST \
    lib/icon_floppy.asm lib/icon_ide.asm lib/icon_clock.asm lib/icon_trash.asm \
    lib/icon_geobench.asm lib/icon_basic.asm lib/icon_binary.asm \
    lib/icon_picture.asm lib/icon_text.asm

"$RASM" desktop/main.asm -eo          # -eo: overwrite the .dsk if it exists
echo "Built build/geobench.dsk + build/GEOBENCH.RAW"
