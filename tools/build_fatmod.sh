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
"$RASM" kernel/modules/gbfat.asm -eo
echo "Built build/GBFAT.RAW ($(stat -c%s build/GBFAT.RAW) bytes)"
