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
"$RASM" kernel/modules/floppysv.asm -eo
echo "Built build/FLOPPYSV.RAW ($(stat -c%s build/FLOPPYSV.RAW) bytes)"
