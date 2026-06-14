#!/usr/bin/env bash
# Build GEOBENCH.ROM - the 16K loadable upper-ROM driver image (#152).
# Output: rom/GEOBENCH.ROM (16K, headerless). Drop it into a free [expansion_roms]
# slot in the 1984 config and the boot probe finds it by its "GBROM" signature.
set -euo pipefail
cd "$(dirname "$0")/.."
RASM="${RASM:-rasm}"
"$RASM" rom/geobench_rom.asm -eo
sz=$(stat -c%s rom/GEOBENCH.ROM)
echo "Built rom/GEOBENCH.ROM ($sz bytes)"
[ "$sz" -eq 16384 ] || { echo "ERROR: expected 16384 bytes (16K)"; exit 1; }
