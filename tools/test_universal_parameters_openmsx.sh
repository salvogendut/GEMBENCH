#!/usr/bin/env bash
# Production UI plus injected public-service boundary/interrupt checks.
set -euo pipefail
cd "$(dirname "$0")/.."
export GEOBENCH_PARAMETER_CODE_END="0x$(awk '$1 == "UP_REQUEST" {sub(/^#/, "", $2); print $2; exit}' build/msx/gbapv4.sym)"
export GEOBENCH_ACCESSORY_SCRIPT=debug/parameters_openmsx.tcl
export MSX_HEADLESS=1
bash tools/test_desk_accessories_openmsx.sh
