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

python3 tools/genfont.py build/DEFAULT.FNT   # 6x8 font, loaded into PAGE_DATA
"$RASM" apps/hello/hello.asm -eo             # -> build/HELLO.RAW
"$RASM" kernel/gbkern.asm -eo                # incbins HELLO.RAW + DEFAULT.FNT -> .dsk
echo "Built build/gbkern.dsk (GBKERN + HELLO + DEFAULT.FNT)"
