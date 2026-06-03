#!/usr/bin/env bash
# Build the GEOBENCH banked-kernel skeleton + the HELLO app (Phase 1 proof).
#
# Apps are separate binaries; the app is built FIRST because the kernel incbins
# build/HELLO.RAW. Output: build/gbkern.dsk (GBKERN.BIN, with HELLO embedded).
#   tools/build_kernel.sh
#   1984 --memory=128 --disk-a=build/gbkern.dsk --autostart=GBKERN
set -euo pipefail

cd "$(dirname "$0")/.."          # repo root
RASM="${RASM:-rasm}"

mkdir -p build
rm -f build/gbkern.dsk                        # save-to-DSK appends; start clean

python3 tools/genfont.py build/DEFAULT.FNT   # 6x8 font -> PAGE_DATA
python3 tools/packicons.py build/DEFAULT.IST \
    lib/icon_floppy.asm lib/icon_ide.asm lib/icon_clock.asm lib/icon_trash.asm \
    lib/icon_geobench.asm lib/icon_basic.asm lib/icon_binary.asm \
    lib/icon_picture.asm lib/icon_text.asm            # icon set -> PAGE_DATA
"$RASM" apps/desktop/desktop.asm -eo         # -> build/DESKTOP.RAW
"$RASM" apps/filemgr/filemgr.asm -eo         # -> build/FILEMGR.RAW
tools/build_capp.sh apps/viewer build/VIEWER.RAW   # VIEWER (C/SDCC) -> build/VIEWER.RAW
tools/build_capp.sh apps/chello build/CHELLO.RAW   # C app (SDCC) -> build/CHELLO.RAW
"$RASM" kernel/gbkern.asm -eo                # incbins apps + font + icons -> .dsk
echo "Built build/gbkern.dsk (GBKERN + DESKTOP + FILEMGR + VIEWER + CHELLO + assets)"
