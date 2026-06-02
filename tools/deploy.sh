#!/usr/bin/env bash
# Build GEOBENCH and deploy it onto the Cyboard/SymbiFace IDE image, so UniDOS
# can RUN"GEOBENCH off the IDE volume.
#
#   tools/deploy.sh
#
# The IDE image defaults to ~/Downloads/GEOBENCH.IMG (override with
# GEOBENCH_IMG). It is a raw FAT16 image; files are copied in with mtools, so
# no root / loopback mount is needed. Make sure the emulator is not running (and
# thus holding the image) when deploying.
#
# Run it afterwards with, e.g.:
#   ../1984/1984 --6128 --paste='run"geobench\n'
set -euo pipefail

cd "$(dirname "$0")/.."                       # repo root
RASM="${RASM:-rasm}"
IMG="${GEOBENCH_IMG:-$HOME/Downloads/GEOBENCH.IMG}"

[ -f "$IMG" ] || { echo "IDE image not found: $IMG" >&2; exit 1; }

mkdir -p build
"$RASM" desktop/main.asm -eo                  # -> build/GEOBENCH.RAW + .dsk
python3 tools/amsdos_header.py build/GEOBENCH.RAW build/GEOBENCH.BIN GEOBENCH BIN 0x4000

MTOOLS_SKIP_CHECK=1 mcopy -o -i "$IMG" build/GEOBENCH.BIN ::/
echo "Deployed GEOBENCH.BIN -> $IMG"
