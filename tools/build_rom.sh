#!/usr/bin/env bash
# Build the GEOBENCH 16K loadable upper-ROM driver images, one per storage card (#152).
#   rom/GEOBENCH.ROM  - IDE (SYMBiFACE) variant: FAT core + gbfat write + IDE read + floppy
#   rom/GBALB.ROM     - Albireo (CH376) variant: CH376 read/write/dir + floppy
# Both are headerless 16K; drop the matching one into a free [expansion_roms] slot and the
# boot probe finds it by its "GBROM" signature.
set -euo pipefail
cd "$(dirname "$0")/.."
RASM="${RASM:-rasm}"
"$RASM" rom/geobench_rom.asm -eo                         # IDE  -> rom/GEOBENCH.ROM
"$RASM" rom/geobench_rom.asm -eo -DSTORAGE_ALBIREO=1     # Albireo -> rom/GBALB.ROM
for rom in rom/GEOBENCH.ROM rom/GBALB.ROM; do
    sz=$(stat -c%s "$rom")
    echo "Built $rom ($sz bytes)"
    [ "$sz" -eq 16384 ] || { echo "ERROR: $rom expected 16384 bytes (16K)"; exit 1; }
done
