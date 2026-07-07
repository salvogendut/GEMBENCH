#!/usr/bin/env bash
# build.sh - assemble + run the PCW boot/video spike (#331 Phase 1).
#
# Boots a GEOBENCH-format disc in the 1985 emulator headless and
# screenshots the CGA test pattern:
#   bash tools/pcwspike/build.sh
# Outputs: build/pcwspike.dsk, build/pcwspike.png
set -euo pipefail

cd "$(dirname "$0")/../.."
RASM="${RASM:-rasm}"
E1985="${E1985:-$HOME/Dev/1985/1985}"
mkdir -p build

# rasm exits 0 on assembly errors - remove outputs first, assert after
rm -f build/pcwboot.bin build/pcwspike.bin
"$RASM" kernel/pcwboot.asm
[ -s build/pcwboot.bin ] || { echo "ERROR: pcwboot.bin not produced" >&2; exit 1; }
"$RASM" tools/pcwspike/spike.asm
[ -s build/pcwspike.bin ] || { echo "ERROR: pcwspike.bin not produced" >&2; exit 1; }

python3 tools/mkpcwdsk.py build/pcwspike.dsk \
    --boot build/pcwboot.bin --sys build/pcwspike.bin --load 0x1000

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$E1985" \
    --config debug/1985-pcw.conf \
    --disk-a build/pcwspike.dsk \
    --screenshot-at 250:build/pcwspike.ppm \
    --exit-after 300

python3 - <<'EOF'
from PIL import Image
Image.open('build/pcwspike.ppm').save('build/pcwspike.png')
print('build/pcwspike.png written')
EOF
